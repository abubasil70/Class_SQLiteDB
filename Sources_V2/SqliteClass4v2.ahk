#Requires AutoHotkey v2.0

; ======================================================================================================================
; SimpleSQLite Class - Standalone SQLite Database Manager for AutoHotkey v2
; ======================================================================================================================
; Description: A comprehensive SQLite database management class with full UTF-8/UTF-16 support
; Requirements: sqlite3.dll (download from https://www.sqlite.org/2026/sqlite-dll-win-x64-3510200.zip)
; Author: Enhanced version with full Unicode support
; Version: 2.0
; ======================================================================================================================

class SimpleSQLite {
    ; ==================================================================================
    ; Properties
    ; ==================================================================================
    db := 0                    ; Database handle
    dllPath := ""              ; Path to sqlite3.dll
    hDll := 0                  ; DLL handle
    
    ; ==================================================================================
    ; Constructor - Initialize and open database
    ; ==================================================================================
    ; Parameters:
    ;   dbPath - Full path to the database file
    ;   dllPath - (Optional) Path to sqlite3.dll, defaults to script directory
    ; ==================================================================================
    __New(dbPath, dllPath := "") {
        ; Set DLL path
        if (dllPath = "")
            this.dllPath := A_ScriptDir . "\sqlite3.dll"
        else
            this.dllPath := dllPath
        
        ; Check if DLL exists
        if !FileExist(this.dllPath) {
            MsgBox("sqlite3.dll not found!`n`nPlease download it from:`nhttps://www.sqlite.org/download.html`n`nAnd place it in: " . A_ScriptDir, "Error", 16)
            return
        }
        
        ; Load DLL
        this.hDll := DllCall("LoadLibrary", "Str", this.dllPath, "Ptr")
        if !this.hDll {
            MsgBox("Failed to load sqlite3.dll!", "Error", 16)
            return
        }
        
        ; Open database
        this.Open(dbPath)
    }
    
    ; ==================================================================================
    ; Open - Open or create a database file
    ; ==================================================================================
    ; Parameters:
    ;   dbPath - Full path to the database file
    ; Returns:
    ;   true if successful, false otherwise
    ; ==================================================================================
    Open(dbPath) {
        pDb := 0
        ; Using sqlite3_open16 for full Unicode support
        result := DllCall(this.dllPath . "\sqlite3_open16", "WStr", dbPath, "Ptr*", &pDb, "Cdecl Int")
        
        if (result != 0) {
            MsgBox("Failed to open database: " . result)
            return false
        }
        
        this.db := pDb
        
        ; Enable UTF-8 encoding
        this.Exec16("PRAGMA encoding = 'UTF-8'")
        
        return true
    }
    
    ; ==================================================================================
    ; Close - Close the database connection
    ; ==================================================================================
    Close() {
        if (this.db)
            DllCall(this.dllPath . "\sqlite3_close", "Ptr", this.db, "Cdecl Int")
        this.db := 0
    }
    
    ; ==================================================================================
    ; Exec16 - Execute SQL statement using UTF-16 encoding
    ; ==================================================================================
    ; Parameters:
    ;   sql - SQL statement to execute
    ; Returns:
    ;   true if successful, false otherwise
    ; Usage:
    ;   db.Exec16("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
    ; ==================================================================================
    Exec16(sql) {
        if (!this.db)
            return false
        
        pStmt := 0
        result := DllCall(this.dllPath . "\sqlite3_prepare16_v2"
            , "Ptr", this.db
            , "WStr", sql
            , "Int", -1
            , "Ptr*", &pStmt
            , "Ptr", 0
            , "Cdecl Int")
        
        if (result != 0 || !pStmt) {
            this._ShowError()
            return false
        }
        
        result := DllCall(this.dllPath . "\sqlite3_step", "Ptr", pStmt, "Cdecl Int")
        DllCall(this.dllPath . "\sqlite3_finalize", "Ptr", pStmt, "Cdecl Int")
        
        return (result = 101)  ; SQLITE_DONE
    }
    
    ; ==================================================================================
    ; Exec - Legacy execute function (alias for Exec16)
    ; ==================================================================================
    Exec(sql) {
        return this.Exec16(sql)
    }
    
    ; ==================================================================================
    ; InsertWithParams - Insert data using parameterized queries (prevents SQL injection)
    ; ==================================================================================
    ; Parameters:
    ;   sql - SQL statement with ? placeholders
    ;   params* - Variable number of parameters to bind
    ; Returns:
    ;   true if successful, false otherwise
    ; Usage:
    ;   db.InsertWithParams("INSERT INTO users (name, age) VALUES (?, ?)", "أحمد", 30)
    ; ==================================================================================
    InsertWithParams(sql, params*) {
        if (!this.db)
            return false
        
        pStmt := 0
        result := DllCall(this.dllPath . "\sqlite3_prepare16_v2"
            , "Ptr", this.db
            , "WStr", sql
            , "Int", -1
            , "Ptr*", &pStmt
            , "Ptr", 0
            , "Cdecl Int")
        
        if (result != 0 || !pStmt) {
            this._ShowError()
            return false
        }
        
        ; Bind parameters
        for index, param in params {
            if (Type(param) = "String") {
                ; Use sqlite3_bind_text16 for text
                DllCall(this.dllPath . "\sqlite3_bind_text16"
                    , "Ptr", pStmt
                    , "Int", index
                    , "WStr", param
                    , "Int", -1
                    , "Ptr", -1  ; SQLITE_TRANSIENT
                    , "Cdecl Int")
            } else if (Type(param) = "Integer") {
                DllCall(this.dllPath . "\sqlite3_bind_int"
                    , "Ptr", pStmt
                    , "Int", index
                    , "Int", param
                    , "Cdecl Int")
            } else if (Type(param) = "Float") {
                DllCall(this.dllPath . "\sqlite3_bind_double"
                    , "Ptr", pStmt
                    , "Int", index
                    , "Double", param
                    , "Cdecl Int")
            }
        }
        
        result := DllCall(this.dllPath . "\sqlite3_step", "Ptr", pStmt, "Cdecl Int")
        DllCall(this.dllPath . "\sqlite3_finalize", "Ptr", pStmt, "Cdecl Int")
        
        return (result = 101)  ; SQLITE_DONE
    }
    
    ; ==================================================================================
    ; Query - Execute SELECT query and return results
    ; ==================================================================================
    ; Parameters:
    ;   sql - SELECT statement
    ; Returns:
    ;   Array of Map objects, each representing a row
    ; Usage:
    ;   rows := db.Query("SELECT * FROM users WHERE age > 25")
    ;   for row in rows {
    ;       MsgBox(row["name"] . " - " . row["age"])
    ;   }
    ; ==================================================================================
    Query(sql) {
        if (!this.db)
            return []
        
        pStmt := 0
        ; Use sqlite3_prepare16_v2 for Unicode support
        result := DllCall(this.dllPath . "\sqlite3_prepare16_v2"
            , "Ptr", this.db
            , "WStr", sql
            , "Int", -1
            , "Ptr*", &pStmt
            , "Ptr", 0
            , "Cdecl Int")
        
        if (result != 0 || !pStmt) {
            this._ShowError()
            return []
        }
        
        colCount := DllCall(this.dllPath . "\sqlite3_column_count", "Ptr", pStmt, "Cdecl Int")
        
        ; Get column names
        columns := []
        Loop colCount {
            pName := DllCall(this.dllPath . "\sqlite3_column_name16", "Ptr", pStmt, "Int", A_Index - 1, "Cdecl Ptr")
            columns.Push(StrGet(pName, "UTF-16"))
        }
        
        ; Fetch rows
        rows := []
        while (DllCall(this.dllPath . "\sqlite3_step", "Ptr", pStmt, "Cdecl Int") = 100) {  ; SQLITE_ROW
            row := Map()
            Loop colCount {
                colIdx := A_Index - 1
                colName := columns[A_Index]
                colType := DllCall(this.dllPath . "\sqlite3_column_type", "Ptr", pStmt, "Int", colIdx, "Cdecl Int")
                
                ; Get value based on type
                switch colType {
                    case 1:  ; INTEGER
                        value := DllCall(this.dllPath . "\sqlite3_column_int", "Ptr", pStmt, "Int", colIdx, "Cdecl Int")
                    case 2:  ; FLOAT
                        value := DllCall(this.dllPath . "\sqlite3_column_double", "Ptr", pStmt, "Int", colIdx, "Cdecl Double")
                    case 3:  ; TEXT
                        ; Use sqlite3_column_text16 for Unicode support
                        pText := DllCall(this.dllPath . "\sqlite3_column_text16", "Ptr", pStmt, "Int", colIdx, "Cdecl Ptr")
                        value := StrGet(pText, "UTF-16")
                    default:  ; NULL or BLOB
                        value := ""
                }
                row[colName] := value
            }
            rows.Push(row)
        }
        
        DllCall(this.dllPath . "\sqlite3_finalize", "Ptr", pStmt, "Cdecl Int")
        return rows
    }
    
    ; ==================================================================================
    ; GetLastInsertID - Get the ID of the last inserted row
    ; ==================================================================================
    ; Returns:
    ;   Integer - The last inserted row ID
    ; ==================================================================================
    GetLastInsertID() {
        if (!this.db)
            return 0
        return DllCall(this.dllPath . "\sqlite3_last_insert_rowid", "Ptr", this.db, "Cdecl Int64")
    }
    
    ; ==================================================================================
    ; GetChangesCount - Get number of rows affected by last operation
    ; ==================================================================================
    ; Returns:
    ;   Integer - Number of affected rows
    ; ==================================================================================
    GetChangesCount() {
        if (!this.db)
            return 0
        return DllCall(this.dllPath . "\sqlite3_changes", "Ptr", this.db, "Cdecl Int")
    }
    
    ; ==================================================================================
    ; BeginTransaction - Start a database transaction
    ; ==================================================================================
    BeginTransaction() {
        return this.Exec("BEGIN TRANSACTION")
    }
    
    ; ==================================================================================
    ; Commit - Commit current transaction
    ; ==================================================================================
    Commit() {
        return this.Exec("COMMIT")
    }
    
    ; ==================================================================================
    ; Rollback - Rollback current transaction
    ; ==================================================================================
    Rollback() {
        return this.Exec("ROLLBACK")
    }
    
    ; ==================================================================================
    ; TableExists - Check if a table exists in the database
    ; ==================================================================================
    ; Parameters:
    ;   tableName - Name of the table to check
    ; Returns:
    ;   true if table exists, false otherwise
    ; ==================================================================================
    TableExists(tableName) {
        cleanName := StrReplace(tableName, "'", "''")
        result := this.Query("SELECT name FROM sqlite_master WHERE type='table' AND name='" . cleanName . "'")
        return (result.Length > 0)
    }
    
    ; ==================================================================================
    ; _ShowError - Display SQLite error message (internal use)
    ; ==================================================================================
    _ShowError() {
        if (!this.db)
            return
        
        pErr := DllCall(this.dllPath . "\sqlite3_errmsg16", "Ptr", this.db, "Cdecl Ptr")
        if (pErr) {
            error := StrGet(pErr, "UTF-16")
            MsgBox("SQL Error: " . error, "Database Error", 16)
        }
    }
    
    ; ==================================================================================
    ; Destructor - Clean up when object is destroyed
    ; ==================================================================================
    __Delete() {
        this.Close()
        if (this.hDll)
            DllCall("FreeLibrary", "Ptr", this.hDll)
    }
}

; ======================================================================================================================
; Usage Examples
; ======================================================================================================================
/*
; Example 1: Create database and table
db := SimpleSQLite("test.db")
db.Exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)")

; Example 2: Insert data (safe from SQL injection)
db.InsertWithParams("INSERT INTO users (name, age) VALUES (?, ?)", "أحمد محمد", 30)
db.InsertWithParams("INSERT INTO users (name, age) VALUES (?, ?)", "فاطمة علي", 25)

; Example 3: Query data
rows := db.Query("SELECT * FROM users")
for row in rows {
    MsgBox("Name: " . row["name"] . "`nAge: " . row["age"])
}

; Example 4: Update data
db.Exec("UPDATE users SET age = 31 WHERE name = 'أحمد محمد'")

; Example 5: Using transactions
db.BeginTransaction()
try {
    db.InsertWithParams("INSERT INTO users (name, age) VALUES (?, ?)", "سارة", 28)
    db.InsertWithParams("INSERT INTO users (name, age) VALUES (?, ?)", "خالد", 35)
    db.Commit()
} catch as e {
    db.Rollback()
    MsgBox("Transaction failed: " . e.Message)
}

; Example 6: Check if table exists
if (db.TableExists("users"))
    MsgBox("Table 'users' exists!")

; Example 7: Get last inserted ID
db.InsertWithParams("INSERT INTO users (name, age) VALUES (?, ?)", "محمود", 40)
lastID := db.GetLastInsertID()
MsgBox("Last inserted ID: " . lastID)

; Database will be automatically closed when db object is destroyed
*/
