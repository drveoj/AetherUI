"""Length of an Ogg Vorbis file, read from the container.

Durations in a content pack are never hand-written: the console predicts the end
of a segment from the manifest rather than being told about it by the client, so
a number that is a second out is a second of clipped audio every time it plays.

Reads the granule position off the last page and divides by the sample rate off
the first. No dependencies, and exact - the granule position IS the sample
count, so this is the file's own answer rather than an estimate from a bitrate.
"""

import struct

CAPTURE = b"OggS"


def _first_page(fh):
    """The identification header, which is always the first packet."""
    fh.seek(0)
    head = fh.read(4096)
    if not head.startswith(CAPTURE):
        raise ValueError("not an Ogg stream")

    at = head.find(b"\x01vorbis")
    if at < 0:
        raise ValueError("no Vorbis identification header")

    # version(4) channels(1) rate(4), from just past the packet type and magic.
    body = head[at + 7:at + 16]
    _, channels, rate = struct.unpack("<IBI", body)
    if rate <= 0:
        raise ValueError("sample rate of zero")
    return channels, rate


def _last_granule(fh):
    """The granule position of the final page: total samples in the stream.

    Searched backwards from the end rather than by walking pages forward. A
    four-minute track is a few thousand pages and walking them all takes long
    enough to notice when a season has eleven of them.
    """
    fh.seek(0, 2)
    size = fh.tell()

    window = 65536
    at = max(0, size - window)
    while True:
        fh.seek(at)
        chunk = fh.read(min(window, size - at))
        found = chunk.rfind(CAPTURE)
        if found >= 0:
            # granule position is eight bytes at offset 6 of the page header.
            page = chunk[found:found + 14]
            if len(page) == 14:
                return struct.unpack("<q", page[6:14])[0]
        if at == 0:
            raise ValueError("no final Ogg page")
        at = max(0, at - window)


def duration(path):
    """Seconds, as a float."""
    with open(path, "rb") as fh:
        _, rate = _first_page(fh)
        granule = _last_granule(fh)
    if granule <= 0:
        raise ValueError("final page carries no granule position")
    return granule / float(rate)


if __name__ == "__main__":
    import sys

    for name in sys.argv[1:]:
        secs = duration(name)
        print("%7.2f  %d:%02d  %s" % (secs, secs // 60, secs % 60, name))
