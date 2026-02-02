import { useState, useEffect, useCallback } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useSWRConfig } from 'swr';
import { getCart, clearCart } from '../../api/cartApi';
import { createOrder } from '../../api/orderApi';
import { useToast } from '../../components/common/ToastProvider';
import { toUserFriendlyError } from '../../utils/errorMessages';

/**
 * Checkout Page - Create order
 * POST /api/v1/orders
 * user_id extracted from auth token by backend
 */
export default function CheckoutPage() {
    const navigate = useNavigate();
    const { notify } = useToast();
    const { mutate } = useSWRConfig();
    const [cart, setCart] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [submitting, setSubmitting] = useState(false);
    const [orderResult, setOrderResult] = useState(null);

    const fetchCart = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const result = await getCart();
            setCart(result);
            if (import.meta.env.DEV) {
                console.log('[API] GET /cart:', result);
            }
        } catch (err) {
            const message = toUserFriendlyError(err?.message);
            setError(message);
            notify('error', message);
            if (import.meta.env.DEV) {
                console.error('[API ERROR]', err);
            }
        } finally {
            setLoading(false);
        }
    }, [notify]);

    useEffect(() => {
        const token = localStorage.getItem('authToken');
        if (!token) {
            navigate('/login?returnTo=/checkout');
            return;
        }
        fetchCart();
    }, [navigate, fetchCart]);

    const handleSubmitOrder = async (e) => {
        e.preventDefault();
        setSubmitting(true);
        setError(null);

        try {
            const orderData = {
                items: cart.items.map(item => ({
                    product_id: item.product_id,
                    product_name: item.product_name,
                    quantity: item.quantity,
                    price: item.product_price
                }))
            };

            const result = await createOrder(orderData);
            if (import.meta.env.DEV) {
                console.log('[API] POST /orders:', result);
            }
            setOrderResult(result);
            notify('success', 'Order created successfully!');

            // Clear cart immediately for UI + backend consistency
            try {
                await clearCart();
                // Refresh cart badge (App.jsx uses SWR key: 'cart-count')
                await mutate('cart-count');
            } catch (clearErr) {
                const message = toUserFriendlyError(clearErr?.message);
                notify('error', `Order created, but failed to clear cart: ${message}`);
            }
        } catch (err) {
            const message = toUserFriendlyError(err?.message);
            notify('error', message);
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

            {/* Empty Cart - only when load succeeded but cart is empty */}
            {!loading && !orderResult && !error && (!cart || !cart.items || cart.items.length === 0) && (
                <div className="empty">
                    <p>Cart is empty. Add items first.</p>
                    <Link to="/">Browse Products</Link>
                </div>
            )}

            {/* Cart Load Error - Retry */}
            {!loading && !orderResult && error && (!cart?.items?.length) && (
                <div className="error-box">
                    <strong>Error:</strong> {error}
                    <button
                        type="button"
                        className="primary"
                        style={{ marginTop: '0.75rem' }}
                        onClick={fetchCart}
                    >
                        Try Again
                    </button>
                </div>
            )}

            {/* Checkout Form */}
            {!loading && !orderResult && cart?.items?.length > 0 && (
                <>
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
