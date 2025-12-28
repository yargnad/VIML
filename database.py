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
    # Create tables
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS persons (
            person_id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_path TEXT NOT NULL,
            name TEXT NOT NULL,
            title TEXT,
            organization TEXT,
            role TEXT DEFAULT 'Unknown'
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS identifiers (
            identifier_id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER NOT NULL,
            method TEXT NOT NULL,
            biometric_data BLOB NOT NULL,
            FOREIGN KEY(person_id) REFERENCES persons(person_id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS occurrences (
            occurrence_id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_path TEXT NOT NULL,
            person_id INTEGER NOT NULL,
            timestamp_seconds REAL NOT NULL,
            method_used TEXT NOT NULL CHECK(method_used IN ('ocr', 'face', 'voice')),
            confidence REAL,
            details TEXT,
            review_status TEXT DEFAULT 'pending' CHECK(review_status IN ('pending', 'approved', 'rejected')),
            job_id TEXT,
            FOREIGN KEY(person_id) REFERENCES persons(person_id)
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS jobs (
            job_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            result TEXT,
            config TEXT,
            auto_approve BOOLEAN DEFAULT 0
        )
    ''')
    
    # --- MIGRATIONS (for existing databases) ---
    # Check for missing columns and add them if they don't exist
    
    # persons: title, organization, role
    try:
        cursor.execute("ALTER TABLE persons ADD COLUMN title TEXT")
    except sqlite3.OperationalError: pass # Column likely exists
    try:
        cursor.execute("ALTER TABLE persons ADD COLUMN organization TEXT")
    except sqlite3.OperationalError: pass
    try:
        cursor.execute("ALTER TABLE persons ADD COLUMN role TEXT DEFAULT 'Unknown'")
    except sqlite3.OperationalError: pass
    
    # occurrences: review_status, job_id
    try:
        cursor.execute("ALTER TABLE occurrences ADD COLUMN review_status TEXT DEFAULT 'pending'")
    except sqlite3.OperationalError: pass
    try:
        cursor.execute("ALTER TABLE occurrences ADD COLUMN job_id TEXT")
    except sqlite3.OperationalError: pass
    
    # jobs: config, auto_approve
    try:
        cursor.execute("ALTER TABLE jobs ADD COLUMN config TEXT")
    except sqlite3.OperationalError: pass
    try:
        cursor.execute("ALTER TABLE jobs ADD COLUMN auto_approve BOOLEAN DEFAULT 0")
    except sqlite3.OperationalError: pass

    conn.commit()
    conn.close()
    print("Database initialized successfully.")