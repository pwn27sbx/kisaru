import argparse
import os
import sys

# The entry point sits one level below scripts/, where app_meta lives. The other
# backends (manga_server.py, anime_server.py) are scripts themselves, so their
# own folder is sys.path[0]; this one has to say it.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.dirname(_HERE))

from server import PORT, run  # noqa: E402

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="kisaru novel backend")
    parser.add_argument("--port", type=int, default=PORT,
                        help=f"Port to listen on (default: {PORT})")
    run(parser.parse_args().port)
