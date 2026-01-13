import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import PlaceholderImage from '../../components/common/PlaceholderImage';
import { DetailSkeleton } from '../../components/common/Skeleton';
import EmptyState from '../../components/common/EmptyState';
import ApiError from '../../components/common/ApiError';
import QuantitySelector from '../../components/domain/QuantitySelector';
import { getProductDetails } from '../../api/productApi';
import { addToCart } from '../../api/cartApi';
import { getReviews } from '../../api/reviewApi';

/**
 * ProductDetailPage
 * API: GET /api/v1/products/:id/details (Phase 1 aggregation)
 * API: GET /api/v1/reviews?product_id={id}
 * 
 * Responsibilities:
 * - Fetch product details from API
 * - Fetch product reviews from API
 * - Handle add to cart action
 * - Pass data to domain components
 */
export default function ProductDetailPage() {
    const { id } = useParams();
    const [data, setData] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    const [reviews, setReviews] = useState([]);
    const [reviewsLoading, setReviewsLoading] = useState(false);

    const [quantity, setQuantity] = useState(1);
    const [adding, setAdding] = useState(false);
    const [cartMessage, setCartMessage] = useState(null);

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

    // Fetch reviews separately
    useEffect(() => {
        async function fetchReviews() {
            setReviewsLoading(true);
            try {
                const result = await getReviews(id);
                setReviews(result);
                console.log('[API] GET /reviews?product_id=' + id + ':', result);
            } catch (err) {
                console.error('[API ERROR] Reviews:', err);
                // Don't show error for reviews, just show empty state
            } finally {
                setReviewsLoading(false);
            }
        }
        fetchReviews();
    }, [id]);

    const handleAddToCart = async () => {
        setAdding(true);
        setCartMessage(null);
        try {
            const result = await addToCart(id, quantity);
            console.log('[API] POST /cart:', result);
            setCartMessage({ type: 'success', text: `Added ${quantity} to cart` });
            setQuantity(1);
        } catch (err) {
            setCartMessage({ type: 'error', text: err.message });
            console.error('[API ERROR]:', err);
        } finally {
            setAdding(false);
        }
    };

    // Calculate average rating
    const averageRating = reviews.length > 0
        ? (reviews.reduce((sum, r) => sum + r.rating, 0) / reviews.length).toFixed(1)
        : 0;

    return (
        <div className="page container">
            <Link to="/" className="back-link">← Back to Products</Link>
            <p className="api-label">API: GET /api/v1/products/{id}/details</p>

            {/* Loading State */}
            {loading && <DetailSkeleton />}

            {/* Error State */}
            {!loading && error && (
                <ApiError error={error} endpoint={`GET /api/v1/products/${id}/details`} />
            )}

            {/* Empty State */}
            {!loading && !error && !data?.product && (
                <EmptyState message="Product not found" icon="🔍" />
            )}

            {/* Success State */}
            {!loading && !error && data?.product && (
                <>
                    <div className="detail-layout">
                        {/* Left: Placeholder Image */}
                        <div className="detail-image">
                            <PlaceholderImage size="large" label="Product Image" />
                        </div>

                        {/* Right: Product Info */}
                        <div className="detail-info">
                            <h1>{data.product.name}</h1>
                            <p className="detail-description">{data.product.description}</p>
                            <p className="detail-price">${data.product.price}</p>

                            {/* Stock Status */}
                            {data.stock && (
                                <p className={data.stock.available ? 'stock-available' : 'stock-out'}>
                                    {data.stock.available
                                        ? `In Stock (${data.stock.quantity})`
                                        : 'Out of Stock'}
                                </p>
                            )}

                            {/* Quantity Selector */}
                            <QuantitySelector
                                quantity={quantity}
                                onChange={setQuantity}
                                min={1}
                            />

                            {/* Add to Cart Button */}
                            <button
                                className="btn-primary add-to-cart-btn"
                                onClick={handleAddToCart}
                                disabled={adding || !data.stock?.available}
                            >
                                {adding ? 'Adding...' : 'Add to Cart'}
                            </button>

                            {/* Feedback Message */}
                            {cartMessage && (
                                <p className={cartMessage.type === 'success' ? 'success-text' : 'error-text'}>
                                    {cartMessage.text}
                                </p>
                            )}
                        </div>
                    </div>

                    {/* Reviews Section */}
                    <div className="reviews-section" style={{ marginTop: '3rem' }}>
                        <h2>Customer Reviews</h2>

                        {reviewsLoading ? (
                            <p>Loading reviews...</p>
                        ) : reviews.length > 0 ? (
                            <>
                                {/* Average Rating */}
                                <div className="reviews-summary" style={{ marginBottom: '1.5rem', padding: '1rem', background: '#f5f5f5', borderRadius: '8px' }}>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
                                        <div style={{ fontSize: '2rem', fontWeight: 'bold' }}>{averageRating}</div>
                                        <div>
                                            <div style={{ color: '#ffa500', fontSize: '1.2rem' }}>
                                                {'⭐'.repeat(Math.round(averageRating))}
                                            </div>
                                            <div style={{ color: '#666', fontSize: '0.9rem' }}>
                                                Based on {reviews.length} review{reviews.length !== 1 ? 's' : ''}
                                            </div>
                                        </div>
                                    </div>
                                </div>

                                {/* Reviews List */}
                                <div className="reviews-list">
                                    {reviews.map(review => (
                                        <div key={review.id} className="review-item" style={{
                                            padding: '1.5rem',
                                            marginBottom: '1rem',
                                            border: '1px solid #ddd',
                                            borderRadius: '8px'
                                        }}>
                                            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
                                                <div style={{ color: '#ffa500', fontSize: '1.1rem' }}>
                                                    {'⭐'.repeat(review.rating)}
                                                </div>
                                                <div style={{ color: '#888', fontSize: '0.85rem' }}>
                                                    {new Date(review.created_at).toLocaleDateString()}
                                                </div>
                                            </div>
                                            <h4 style={{ margin: '0.5rem 0' }}>{review.title}</h4>
                                            <p style={{ color: '#555', lineHeight: '1.6' }}>{review.comment}</p>
                                            <p style={{ color: '#888', fontSize: '0.85rem', marginTop: '0.5rem' }}>
                                                By User #{review.user_id}
                                            </p>
                                        </div>
                                    ))}
                                </div>
                            </>
                        ) : (
                            <EmptyState message="No reviews yet" icon="📝" />
                        )}
                    </div>
                </>
            )}

            {/* API Debug */}
            {data && (
                <details className="api-debug" style={{ marginTop: '2rem' }}>
                    <summary>API Response</summary>
                    <pre>{JSON.stringify({ product: data, reviews }, null, 2)}</pre>
                </details>
            )}
        </div>
    );
}
