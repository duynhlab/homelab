import { useState, useEffect } from 'react';
import { useParams, Link, useNavigate, useLocation } from 'react-router-dom';
import PlaceholderImage from '../../components/common/PlaceholderImage';
import { DetailSkeleton } from '../../components/common/Skeleton';
import EmptyState from '../../components/common/EmptyState';
import ApiError from '../../components/common/ApiError';
import QuantitySelector from '../../components/domain/QuantitySelector';
import { useToast } from '../../components/common/ToastProvider';
import { getProductDetails } from '../../api/productApi';
import { addToCart } from '../../api/cartApi';
import { getReviews, createReview } from '../../api/reviewApi';

/**
 * ProductDetailPage
 * API: GET /api/v1/products/:id/details
 * API: GET /api/v1/reviews?product_id={id}
 */
export default function ProductDetailPage() {
    const { id } = useParams();
    const navigate = useNavigate();
    const location = useLocation();
    const { notify } = useToast();
    const [data, setData] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    const [reviews, setReviews] = useState([]);
    const [reviewsLoading, setReviewsLoading] = useState(false);

    const [quantity, setQuantity] = useState(1);
    const [adding, setAdding] = useState(false);

    // Auth state
    const isAuthenticated = !!localStorage.getItem('authToken');
    const authUser = (() => {
        try {
            const stored = localStorage.getItem('authUser');
            return stored ? JSON.parse(stored) : null;
        } catch {
            return null;
        }
    })();

    // Review form state
    const [reviewForm, setReviewForm] = useState({ rating: 5, title: '', comment: '' });
    const [submittingReview, setSubmittingReview] = useState(false);

    // Compute hasReviewed: check if current user already has a review for this product
    const hasReviewed = isAuthenticated && authUser?.id && reviews.some(
        (r) => String(r.user_id) === String(authUser.id)
    );

    useEffect(() => {
        async function fetchData() {
            setLoading(true);
            setError(null);
            try {
                const result = await getProductDetails(id);
                setData(result);
                console.log('[API] GET /products/' + id + '/details:', result);
            } catch (err) {
                setError(err.message);
                console.error('[API ERROR]:', err);
            } finally {
                setLoading(false);
            }
        }
        fetchData();
    }, [id]);

    const fetchReviews = async () => {
        setReviewsLoading(true);
        try {
            const result = await getReviews(id);
            setReviews(Array.isArray(result) ? result : []);
            console.log('[API] GET /reviews?product_id=' + id + ':', result);
        } catch (err) {
            console.error('[API ERROR] Reviews:', err);
            setReviews([]);
        } finally {
            setReviewsLoading(false);
        }
    };

    useEffect(() => {
        fetchReviews();
    }, [id]);

    // Auto-scroll to reviews section when #reviews hash is present
    useEffect(() => {
        if (location.hash === '#reviews' && !loading && !reviewsLoading) {
            const reviewsSection = document.getElementById('reviews');
            if (reviewsSection) {
                reviewsSection.scrollIntoView({ behavior: 'smooth' });
            }
        }
    }, [location.hash, loading, reviewsLoading]);

    const handleSubmitReview = async (e) => {
        e.preventDefault();
        if (!authUser?.id) {
            notify('error', 'User not found. Please log in again.');
            return;
        }
        setSubmittingReview(true);
        try {
            const result = await createReview(
                id,
                authUser.id,
                reviewForm.rating,
                reviewForm.title,
                reviewForm.comment
            );
            console.log('[API] POST /reviews:', result);
            notify('success', 'Review submitted!');
            setReviewForm({ rating: 5, title: '', comment: '' });
            // Refresh reviews list
            fetchReviews();
        } catch (err) {
            // Check for 409 Conflict (duplicate review) - fallback for stale UI state
            const isDuplicate = err.response?.status === 409 ||
                (err.message && err.message.toLowerCase().includes('already exists'));
            
            if (isDuplicate) {
                notify('info', 'You have already reviewed this product.');
                // Refresh reviews to update hasReviewed and hide the form
                fetchReviews();
            } else {
                notify('error', err.message || 'Failed to submit review');
            }
            console.error('[API ERROR] Create review:', err);
        } finally {
            setSubmittingReview(false);
        }
    };

    const handleAddToCart = async () => {
        setAdding(true);
        try {
            const result = await addToCart(
                id,
                data.product.name,
                data.product.price,
                quantity
            );
            console.log('[API] POST /cart:', result);
            notify('success', `Added ${quantity} item${quantity > 1 ? 's' : ''} to cart`);
            setQuantity(1);
        } catch (err) {
            notify('error', err.message || 'Failed to add to cart');
            console.error('[API ERROR]:', err);
        } finally {
            setAdding(false);
        }
    };

    const averageRating = reviews.length > 0
        ? (reviews.reduce((sum, r) => sum + r.rating, 0) / reviews.length).toFixed(1)
        : 0;

    // Helper: Safe date formatting with fallback
    const formatReviewDate = (review) => {
        const dateValue = review.created_at || review.createdAt;
        if (!dateValue) return '—';
        const date = new Date(dateValue);
        if (isNaN(date.getTime())) return '—';
        return date.toLocaleDateString();
    };

    // Helper: Author display with fallback
    const getReviewAuthor = (review) => {
        return review.username || review.user_name || 'Guest';
    };

    return (
        <div className="page container">
            <Link to="/" className="back-link">← Back to Products</Link>
            <p className="api-label">API: GET /api/v1/products/{id}/details</p>

            {/* Loading */}
            {loading && <DetailSkeleton />}

            {/* Error */}
            {!loading && error && (
                <ApiError error={error} endpoint={`GET /api/v1/products/${id}/details`} />
            )}

            {/* Empty */}
            {!loading && !error && !data?.product && (
                <EmptyState message="Product not found" icon="🔍" />
            )}

            {/* Product Detail */}
            {!loading && !error && data?.product && (
                <>
                    <div className="detail-layout">
                        <div className="detail-image">
                            <PlaceholderImage size="large" label="Product Image" />
                        </div>

                        <div className="detail-info">
                            <h1>{data.product.name}</h1>
                            <p className="detail-description">{data.product.description}</p>
                            <p className="detail-price">${data.product.price}</p>

                            {data.stock && (
                                <p className={data.stock.available ? 'stock-available' : 'stock-out'}>
                                    {data.stock.available
                                        ? `In Stock (${data.stock.quantity})`
                                        : 'Out of Stock'}
                                </p>
                            )}

                            <QuantitySelector
                                quantity={quantity}
                                onChange={setQuantity}
                                min={1}
                            />

                            <button
                                className="btn-primary add-to-cart-btn"
                                onClick={handleAddToCart}
                                disabled={adding || !data.stock?.available}
                            >
                                {adding ? 'Adding...' : 'Add to Cart'}
                            </button>
                        </div>
                    </div>

                    {/* Reviews */}
                    <div id="reviews" className="reviews-section">
                        <h2>Customer Reviews</h2>

                        {reviewsLoading ? (
                            <p className="text-muted">Loading reviews...</p>
                        ) : reviews.length > 0 ? (
                            <>
                                <div className="reviews-summary">
                                    <span className="reviews-score">{averageRating}</span>
                                    <span className="reviews-stars">{'⭐'.repeat(Math.round(averageRating))}</span>
                                    <span className="text-muted">({reviews.length} reviews)</span>
                                </div>

                                <div className="reviews-list">
                                    {reviews.map(review => (
                                        <div key={review.id} className="review-item">
                                            <div className="review-header">
                                                <span className="review-stars">{'⭐'.repeat(review.rating)}</span>
                                                <span className="text-muted">{formatReviewDate(review)}</span>
                                            </div>
                                            {review.title && <h4>{review.title}</h4>}
                                            <p>{review.comment}</p>
                                            <p className="text-muted">By {getReviewAuthor(review)}</p>
                                        </div>
                                    ))}
                                </div>
                            </>
                        ) : (
                            <EmptyState message="No reviews yet" icon="📝" />
                        )}

                        {/* Write a Review */}
                        <div className="write-review" style={{ marginTop: '1.5rem', paddingTop: '1rem', borderTop: '1px solid var(--border)' }}>
                            <h3>Write a Review</h3>
                            {!isAuthenticated ? (
                                // Not logged in: show login prompt
                                <div className="empty" style={{ padding: '1rem' }}>
                                    <p>Please log in or sign up to write a review.</p>
                                    <div style={{ marginTop: '0.75rem', display: 'flex', gap: '0.5rem', justifyContent: 'center' }}>
                                        <button
                                            className="primary"
                                            onClick={() => navigate(`/login?returnTo=/products/${id}#reviews&mode=login`)}
                                        >
                                            Login
                                        </button>
                                        <button
                                            onClick={() => navigate(`/login?returnTo=/products/${id}#reviews&mode=register`)}
                                        >
                                            Register
                                        </button>
                                    </div>
                                </div>
                            ) : hasReviewed ? (
                                // Already reviewed: show message
                                <div className="empty" style={{ padding: '1rem' }}>
                                    <p>You have already reviewed this product.</p>
                                </div>
                            ) : (
                                // Logged in + not reviewed: show form
                                <form onSubmit={handleSubmitReview}>
                                    <div className="form-group">
                                        <label>Rating</label>
                                        <select
                                            value={reviewForm.rating}
                                            onChange={(e) => setReviewForm({ ...reviewForm, rating: parseInt(e.target.value) })}
                                            style={{ width: 'auto' }}
                                        >
                                            <option value={5}>⭐⭐⭐⭐⭐ (5)</option>
                                            <option value={4}>⭐⭐⭐⭐ (4)</option>
                                            <option value={3}>⭐⭐⭐ (3)</option>
                                            <option value={2}>⭐⭐ (2)</option>
                                            <option value={1}>⭐ (1)</option>
                                        </select>
                                    </div>
                                    <div className="form-group">
                                        <label>Title (optional)</label>
                                        <input
                                            type="text"
                                            placeholder="Summary of your review"
                                            value={reviewForm.title}
                                            onChange={(e) => setReviewForm({ ...reviewForm, title: e.target.value })}
                                        />
                                    </div>
                                    <div className="form-group">
                                        <label>Comment</label>
                                        <textarea
                                            placeholder="Share your thoughts about this product..."
                                            value={reviewForm.comment}
                                            onChange={(e) => setReviewForm({ ...reviewForm, comment: e.target.value })}
                                            rows={3}
                                            style={{ width: '100%', resize: 'vertical' }}
                                            required
                                        />
                                    </div>
                                    <button type="submit" className="primary" disabled={submittingReview}>
                                        {submittingReview ? 'Submitting...' : 'Submit Review'}
                                    </button>
                                </form>
                            )}
                        </div>
                    </div>
                </>
            )}

            {/* API Debug */}
            {data && (
                <details className="api-debug">
                    <summary>API Response</summary>
                    <pre>{JSON.stringify({ product: data, reviews }, null, 2)}</pre>
                </details>
            )}
        </div>
    );
}
