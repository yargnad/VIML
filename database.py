# database.py
import sqlite3

DATABASE_NAME = "video_metadata.db"

def get_db_connection():
    """Establishes a connection to the database."""
    conn = sqlite3.connect(DATABASE_NAME)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """Initializes all database tables."""
    conn = get_db_connection()
    cursor = conn.cursor()

    # Central directory for every unique individual
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS persons (
            person_id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_path TEXT NOT NULL,
            name TEXT NOT NULL,
            UNIQUE(video_path, name)
        );
    ''')

    # Stores the raw biometric data (face embeddings, voice prints)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS identifiers (
            identifier_id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER NOT NULL,
            method TEXT NOT NULL CHECK(method IN ('face', 'voice')),
            biometric_data BLOB NOT NULL,
            FOREIGN KEY(person_id) REFERENCES persons(person_id)
        );
    ''')
    
    # Core event log for every detection
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS occurrences (
            occurrence_id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_path TEXT NOT NULL,
            person_id INTEGER NOT NULL,
            timestamp_seconds REAL NOT NULL,
            method_used TEXT NOT NULL CHECK(method_used IN ('ocr', 'face', 'voice')),
            confidence REAL,
            details TEXT,
            FOREIGN KEY(person_id) REFERENCES persons(person_id)
        );
    ''')
    
    conn.commit()
    conn.close()
    print("Database initialized successfully.")