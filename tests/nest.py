"""Wraps OpenPGP files in one compressed packet.  Usage: nest.py <out> <in> [<in> ...]"""
import struct
import sys
import zlib

data = b"".join(open(p, "rb").read() for p in sys.argv[2:])
compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
body = bytes([1]) + compressor.compress(data) + compressor.flush()  # algorithm 1, ZIP
# New-format header, tag 8, five-octet length so any size fits.
packet = bytes([0xC8, 0xFF]) + struct.pack(">I", len(body)) + body
open(sys.argv[1], "wb").write(packet)
