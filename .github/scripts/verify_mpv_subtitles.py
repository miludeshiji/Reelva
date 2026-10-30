#!/usr/bin/env python3
"""Verify embedded PGS decoding and rendering without starting the application."""

from __future__ import annotations

import argparse
import ctypes as C
import json
import time
from pathlib import Path


class RenderParam(C.Structure):
    _fields_ = [("type", C.c_int), ("data", C.c_void_p)]


def verify(library: Path, fixture: Path) -> None:
    mpv = C.CDLL(str(library.resolve()))
    signatures = {
        "mpv_create": (C.c_void_p, []),
        "mpv_initialize": (C.c_int, [C.c_void_p]),
        "mpv_set_option_string": (C.c_int, [C.c_void_p, C.c_char_p, C.c_char_p]),
        "mpv_get_property_string": (C.c_void_p, [C.c_void_p, C.c_char_p]),
        "mpv_command": (C.c_int, [C.c_void_p, C.POINTER(C.c_char_p)]),
        "mpv_render_context_create": (C.c_int, [C.POINTER(C.c_void_p), C.c_void_p, C.POINTER(RenderParam)]),
        "mpv_render_context_update": (C.c_uint64, [C.c_void_p]),
        "mpv_render_context_render": (C.c_int, [C.c_void_p, C.POINTER(RenderParam)]),
        "mpv_render_context_free": (None, [C.c_void_p]),
        "mpv_free": (None, [C.c_void_p]),
        "mpv_terminate_destroy": (None, [C.c_void_p]),
    }
    for name, (result, arguments) in signatures.items():
        function = getattr(mpv, name)
        function.restype = result
        function.argtypes = arguments

    def checked(result: int) -> None:
        if result < 0:
            raise RuntimeError(f"libmpv operation failed: {result}")

    handle = mpv.mpv_create()
    if not handle:
        raise RuntimeError("libmpv initialization failed")
    renderer = C.c_void_p()
    try:
        for key, value in {
            "config": "no", "terminal": "no", "vo": "libmpv", "ao": "null",
            "hwdec": "no", "sub-auto": "no", "slang": "zh,chi,en",
            "keep-open": "yes", "pause": "no",
        }.items():
            checked(mpv.mpv_set_option_string(handle, key.encode(), value.encode()))
        checked(mpv.mpv_initialize(handle))

        api = C.create_string_buffer(b"sw")
        create_params = (RenderParam * 2)(RenderParam(1, C.cast(api, C.c_void_p)), RenderParam(0, None))
        checked(mpv.mpv_render_context_create(C.byref(renderer), handle, create_params))
        command = (C.c_char_p * 3)(b"loadfile", str(fixture.resolve()).encode("utf-8"), None)
        checked(mpv.mpv_command(handle, command))

        size = (C.c_int * 2)(128, 72)
        pixel_format = C.create_string_buffer(b"rgb0")
        stride = C.c_size_t(128 * 4)
        buffer = C.create_string_buffer(stride.value * 72 + 63)
        pixels_address = (C.addressof(buffer) + 63) & ~63
        pixels = (C.c_ubyte * (stride.value * 72)).from_address(pixels_address)
        block = C.c_int(0)
        render_params = (RenderParam * 6)(
            RenderParam(17, C.cast(size, C.c_void_p)),
            RenderParam(18, C.cast(pixel_format, C.c_void_p)),
            RenderParam(19, C.cast(C.byref(stride), C.c_void_p)),
            RenderParam(20, pixels_address),
            RenderParam(12, C.cast(C.byref(block), C.c_void_p)),
            RenderParam(0, None),
        )
        white_pixels = 0
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if mpv.mpv_render_context_update(renderer) & 1:
                checked(mpv.mpv_render_context_render(renderer, render_params))
                white_pixels = sum(pixels[index] > 200 for index in range(0, len(pixels), 4))
                if white_pixels >= 512:
                    break
            time.sleep(0.01)

        address = mpv.mpv_get_property_string(handle, b"track-list")
        try:
            tracks = json.loads(C.string_at(address).decode("utf-8")) if address else []
        finally:
            if address:
                mpv.mpv_free(address)
        selected = any(
            track.get("codec") == "hdmv_pgs_subtitle"
            and track.get("selected") and not track.get("external")
            for track in tracks
        )
        if not selected or white_pixels < 512:
            raise RuntimeError(f"Embedded PGS failed: selected={selected}, rendered white pixels={white_pixels}")
        print(f"Embedded PGS decoded and rendered: {white_pixels} white pixels")
    finally:
        if renderer.value:
            mpv.mpv_render_context_free(renderer)
        mpv.mpv_terminate_destroy(handle)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path, help="Path to the packaged libmpv shared library")
    parser.add_argument("--fixture", type=Path, default=Path(__file__).resolve().parents[2] / "test/fixtures/player/pgs.mkv")
    arguments = parser.parse_args()
    verify(arguments.library, arguments.fixture)
