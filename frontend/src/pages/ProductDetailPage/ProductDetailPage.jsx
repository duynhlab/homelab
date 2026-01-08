import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import PlaceholderImage from '../../components/common/PlaceholderImage';
import { DetailSkeleton } from '../../components/common/Skeleton';
import EmptyState from '../../components/common/EmptyState';
import ApiError from '../../components/common/ApiError';
import QuantitySelector from '../../components/domain/QuantitySelector';
import { getProductDetails } from '../../api/productApi';
import { addToCart } from '../../api/cartApi';

/**
 * ProductDetailPage
 * API: GET /api/v1/products/:id/details (Phase 1 aggregation)
 * 
 * Responsibilities:
 * - Fetch product details from API
 * - Handle add to cart action
 * - Pass data to domain components
 */
export default function ProductDetailPage() {
    const { id } = useParams();
    const [data, setData] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

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
            )}

            {/* API Debug */}
            {data && (
                <details className="api-debug">
                    <summary>API Response</summary>
                    <pre>{JSON.stringify(data, null, 2)}</pre>
                </details>
            )}
        </div>
    );
}
