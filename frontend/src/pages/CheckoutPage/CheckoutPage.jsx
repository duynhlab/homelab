import { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { getCart } from '../../api/cartApi';
import { createOrder } from '../../api/orderApi';

/**
 * Checkout Page - Create order
 * POST /api/v1/orders
 * Note: user_id is extracted from auth token by backend middleware
 */
export default function CheckoutPage() {
    const navigate = useNavigate();
    const [cart, setCart] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [submitting, setSubmitting] = useState(false);
    const [orderResult, setOrderResult] = useState(null);

    useEffect(() => {
        // Verify user is authenticated
        const token = localStorage.getItem('authToken');
        if (!token) {
            navigate('/login?returnTo=/checkout');
            return;
        }

        async function fetchCart() {
            try {
                const result = await getCart();
                setCart(result);
                if (import.meta.env.DEV) {
                    console.log('[API] GET /cart:', result);
                }
            } catch (err) {
                setError(err.message);
            } finally {
                setLoading(false);
            }
        }
        fetchCart();
    }, [navigate]);

    const handleSubmitOrder = async (e) => {
        e.preventDefault();
        setSubmitting(true);
        setError(null);

        try {
            // user_id is resolved by backend auth middleware from token
            // We no longer send it from frontend
            const orderData = {
                items: cart.items.map(item => ({
                    product_id: item.product_id,
                    quantity: item.quantity,
                    price: item.product_price
                }))
            };

            const result = await createOrder(orderData);
            if (import.meta.env.DEV) {
                console.log('[API] POST /orders:', result);
            }
            setOrderResult(result);
        } catch (err) {
            setError(err.message);
            if (import.meta.env.DEV) {
                console.error('[API ERROR]', err);
            }
        } finally {
            setSubmitting(false);
        }
    };

    return (
        <div className="page container">
            <Link to="/cart" className="back-link">← Back to Cart</Link>
            <h2>Checkout</h2>
            <p className="api-label">API: POST /api/v1/orders</p>

            {/* Loading */}
            {loading && <div className="loading">Loading...</div>}

            {/* Order Success */}
            {orderResult && (
                <>
                    <div className="success">
                        <h3>✅ Order Created Successfully!</h3>
                        <p>Order ID: {orderResult.id}</p>
                        <p>Status: {orderResult.status}</p>
                        <p>Total: ${orderResult.total?.toFixed(2)}</p>
                    </div>
                    <button onClick={() => navigate('/orders')} style={{ marginTop: '0.75rem' }}>
                        View Orders
                    </button>
                    <details className="api-debug">
                        <summary>API Response</summary>
                        <pre>{JSON.stringify(orderResult, null, 2)}</pre>
                    </details>
                </>
            )}

            {/* Empty Cart */}
            {!loading && !orderResult && (!cart || !cart.items || cart.items.length === 0) && (
                <div className="empty">
                    <p>Cart is empty. Add items first.</p>
                    <Link to="/">Browse Products</Link>
                </div>
            )}

            {/* Checkout Form */}
            {!loading && !orderResult && cart?.items?.length > 0 && (
                <>
                    {error && <div className="error">Error: {error}</div>}

                    <div className="two-col">
                        {/* Order Items */}
                        <div className="card">
                            <h3>Order Items</h3>
                            <div className="table-wrapper">
                                <table>
                                    <thead>
                                        <tr>
                                            <th>Product</th>
                                            <th>Qty</th>
                                            <th className="hide-mobile">Price</th>
                                            <th>Subtotal</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {cart.items.map(item => (
                                            <tr key={item.id}>
                                                <td>{item.product_name}</td>
                                                <td>{item.quantity}</td>
                                                <td className="hide-mobile">${item.product_price}</td>
                                                <td>${item.subtotal?.toFixed(2)}</td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </div>

                        {/* Order Summary */}
                        <div className="card">
                            <h3>Order Summary</h3>
                            <table>
                                <tbody>
                                    <tr><th>Subtotal</th><td>${cart.subtotal?.toFixed(2)}</td></tr>
                                    <tr><th>Shipping</th><td>${cart.shipping?.toFixed(2)}</td></tr>
                                    <tr><th><strong>Total</strong></th><td><strong>${cart.total?.toFixed(2)}</strong></td></tr>
                                </tbody>
                            </table>

                            <button
                                className="primary"
                                style={{ width: '100%', marginTop: '0.75rem' }}
                                onClick={handleSubmitOrder}
                                disabled={submitting}
                            >
                                {submitting ? 'Creating Order...' : 'Place Order'}
                            </button>
                        </div>
                    </div>
                </>
            )}
        </div>
    );
}
