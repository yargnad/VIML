# worker.py
import os
from tasks import celery_app

if __name__ == '__main__':
    # Start the worker
    # Note: In production, you would run this via the 'celery' command line tool.
    # This script is a convenience wrapper or for debugging.
    argv = [
        'worker',
        '--loglevel=INFO',
    ]
    celery_app.worker_main(argv)
