package domain

type Notification struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Message string `json:"message"`
	Status  string `json:"status"`
	Read    bool   `json:"read"`
}

type SendEmailRequest struct {
	To      string `json:"to" binding:"required,email"`
	Subject string `json:"subject" binding:"required"`
	Body    string `json:"body" binding:"required"`
}

type SendSMSRequest struct {
	To      string `json:"to" binding:"required"`
	Message string `json:"message" binding:"required"`
}
