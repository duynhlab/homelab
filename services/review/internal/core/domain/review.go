package domain

import "time"

type Review struct {
	ID        string     `json:"id"`
	ProductID string     `json:"product_id"`
	UserID    string     `json:"user_id"`
	Rating    int        `json:"rating"`
	Title     string     `json:"title"`
	Comment   string     `json:"comment"`
	CreatedAt *time.Time `json:"created_at,omitempty"`
}

type CreateReviewRequest struct {
	ProductID string `json:"product_id" binding:"required"`
	UserID    string `json:"user_id" binding:"required"`
	Rating    int    `json:"rating" binding:"required,min=1,max=5"`
	Title     string `json:"title"`
	Comment   string `json:"comment"`
}
