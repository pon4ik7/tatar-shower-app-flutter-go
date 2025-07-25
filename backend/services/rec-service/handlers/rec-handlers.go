package handlers

import (
	"database/sql"
	"encoding/json"
	"github.com/gorilla/mux"
	"github.com/rolanmulukin/tatar-shower-backend/tokens"
	"log"
	"net/http"
	"strings"
)

type Handler struct {
	DB *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{DB: db}
}

func (h *Handler) SetupRoutes() *mux.Router {
	r := mux.NewRouter()
	r.Use(corsMiddleware)

	apiRouter := r.PathPrefix("/api").Subrouter()
	apiRouter.HandleFunc("/streak", h.GetStreak).Methods("GET")
	apiRouter.HandleFunc("/tips", h.GetTips).Methods("GET")

	return r
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (h *Handler) GetStreak(w http.ResponseWriter, r *http.Request) {
	userID, err := tokens.GetUserIDFromRequest(r)
	if err != nil {
		log.Printf("GetStreak auth error: %v", err)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	var currentStreak int
	var lastCompleted sql.NullTime
	err = h.DB.QueryRow(
		`SELECT current_streak, last_completed 
         FROM goals 
         WHERE user_id = $1`,
		userID,
	).Scan(&currentStreak, &lastCompleted)
	if err == sql.ErrNoRows {
		currentStreak = 0
	} else if err != nil {
		log.Printf("GetStreak DB error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	resp := map[string]interface{}{
		"current_streak": currentStreak,
	}
	if lastCompleted.Valid {
		resp["last_completed"] = lastCompleted.Time.Format("2006-01-02")
	} else {
		resp["last_completed"] = nil
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func (h *Handler) GetTips(w http.ResponseWriter, r *http.Request) {
	lang := "en"
	if userID, err := tokens.GetUserIDFromRequest(r); err == nil {
		var uLang string
		if err := h.DB.QueryRow(
			`SELECT language FROM preferences WHERE user_id=$1`, userID,
		).Scan(&uLang); err == nil && uLang != "" {
			lang = uLang
		}
	} else if hdr := r.Header.Get("Accept-Language"); strings.HasPrefix(hdr, "ru") {
		lang = "ru"
	}
	rows, err := h.DB.Query(
		`SELECT message FROM tips WHERE category=$1 ORDER BY id`, lang,
	)
	if err != nil {
		log.Printf("GetTips DB error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	var tips []string
	for rows.Next() {
		var msg string
		if err := rows.Scan(&msg); err != nil {
			log.Printf("GetTips scan error: %v", err)
			continue
		}
		tips = append(tips, msg)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tips)
}
