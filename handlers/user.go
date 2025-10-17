package handlers

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gorilla/mux"
)

type User struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

var (
	users   = make(map[int]*User)
	usersMu sync.RWMutex
	nextID  = 1
)

func init() {
	// Seed with some initial data
	users[1] = &User{ID: 1, Name: "Alice", Email: "alice@example.com"}
	users[2] = &User{ID: 2, Name: "Bob", Email: "bob@example.com"}
	nextID = 3
}

// GetUsers returns all users
func GetUsers(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(50, 150)

	usersMu.RLock()
	defer usersMu.RUnlock()

	userList := make([]*User, 0, len(users))
	for _, user := range users {
		userList = append(userList, user)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(userList)
}

// GetUser returns a single user by ID
func GetUser(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(30, 100)

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		http.Error(w, "Invalid user ID", http.StatusBadRequest)
		return
	}

	usersMu.RLock()
	user, exists := users[id]
	usersMu.RUnlock()

	if !exists {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

// CreateUser creates a new user
func CreateUser(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(100, 300)

	// Randomly return server error to generate error metrics
	if rand.Float32() < 0.05 { // 5% error rate
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var user User
	if err := json.NewDecoder(r.Body).Decode(&user); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	usersMu.Lock()
	user.ID = nextID
	nextID++
	users[user.ID] = &user
	usersMu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(user)
}

// UpdateUser updates an existing user
func UpdateUser(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(80, 250)

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		http.Error(w, "Invalid user ID", http.StatusBadRequest)
		return
	}

	var user User
	if err := json.NewDecoder(r.Body).Decode(&user); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	usersMu.Lock()
	defer usersMu.Unlock()

	if _, exists := users[id]; !exists {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	user.ID = id
	users[id] = &user

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

// DeleteUser deletes a user
func DeleteUser(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(60, 150)

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		http.Error(w, "Invalid user ID", http.StatusBadRequest)
		return
	}

	usersMu.Lock()
	defer usersMu.Unlock()

	if _, exists := users[id]; !exists {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	delete(users, id)
	w.WriteHeader(http.StatusNoContent)
}

// simulateProcessing adds random delay to simulate real processing time
func simulateProcessing(minMs, maxMs int) {
	delay := minMs + rand.Intn(maxMs-minMs+1)
	time.Sleep(time.Duration(delay) * time.Millisecond)
}

