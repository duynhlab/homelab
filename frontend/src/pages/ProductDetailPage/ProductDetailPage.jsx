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
 * API: GET /api/v1/products/:id/details
 * API: GET /api/v1/reviews?product_id={id}
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

    useEffect(() => {
        async function fetchReviews() {
            setReviewsLoading(true);
            try {
                const result = await getReviews(id);
                setReviews(result);
                console.log('[API] GET /reviews?product_id=' + id + ':', result);
            } catch (err) {
                console.error('[API ERROR] Reviews:', err);
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
            const result = await addToCart(
                id,
                data.product.name,
                data.product.price,
                quantity
            );
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

    const averageRating = reviews.length > 0
        ? (reviews.reduce((sum, r) => sum + r.rating, 0) / reviews.length).toFixed(1)
        : 0;

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

                            {cartMessage && (
                                <p className={cartMessage.type === 'success' ? 'success-text' : 'error-text'}>
                                    {cartMessage.text}
                                </p>
                            )}
                        </div>
                    </div>

                    {/* Reviews */}
                    <div className="reviews-section">
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
                                                <span className="text-muted">{new Date(review.created_at).toLocaleDateString()}</span>
                                            </div>
                                            <h4>{review.title}</h4>
                                            <p>{review.comment}</p>
                                            <p className="text-muted">By User #{review.user_id}</p>
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
                <details className="api-debug">
                    <summary>API Response</summary>
                    <pre>{JSON.stringify({ product: data, reviews }, null, 2)}</pre>
                </details>
            )}
        </div>
    );
}
