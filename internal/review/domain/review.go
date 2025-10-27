package domain

type Review struct {
	ID        string `json:"id"`
	ProductID string `json:"productId"`
	UserID    string `json:"userId"`
	Rating    int    `json:"rating"`
	Comment   string `json:"comment"`
}

type CreateReviewRequest struct {
	ProductID string `json:"productId" binding:"required"`
	UserID    string `json:"userId" binding:"required"`
	Rating    int    `json:"rating" binding:"required,min=1,max=5"`
	Comment   string `json:"comment"`
}