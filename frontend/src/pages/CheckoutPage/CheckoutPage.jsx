import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getCart } from '../../api/cartApi';
import { createOrder } from '../../api/orderApi';

/**
 * Checkout Page - Create order
 * POST /api/v1/orders
 */
export default function CheckoutPage() {
    const navigate = useNavigate();
    const [cart, setCart] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [submitting, setSubmitting] = useState(false);
    const [orderResult, setOrderResult] = useState(null);

    useEffect(() => {
        async function fetchCart() {
            try {
                const result = await getCart();
                setCart(result);
                console.log('[API] GET /cart:', result);
            } catch (err) {
                setError(err.message);
            } finally {
                setLoading(false);
            }
        }
        fetchCart();
    }, []);

    const handleSubmitOrder = async (e) => {
        e.preventDefault();
        setSubmitting(true);
        setError(null);

        try {
            // Create order from cart
            const orderData = {
                user_id: '1', // Demo user
                items: cart.items.map(item => ({
                    product_id: item.product_id,
                    quantity: item.quantity,
                    price: item.product_price
                }))
            };

            const result = await createOrder(orderData);
            console.log('[API] POST /orders:', result);
            setOrderResult(result);
        } catch (err) {
            setError(err.message);
            console.error('[API ERROR]', err);
        } finally {
            setSubmitting(false);
        }
    };

    if (loading) return <div className="loading">Loading...</div>;

    // Order success
    if (orderResult) {
        return (
            <div className="page container">
                <div className="success">
                    <h2>✅ Order Created Successfully!</h2>
                    <p>Order ID: {orderResult.id}</p>
                    <p>Status: {orderResult.status}</p>
                    <p>Total: ${orderResult.total?.toFixed(2)}</p>
                </div>
                <button onClick={() => navigate('/orders')} style={{ marginTop: '1rem' }}>
                    View Orders
                </button>

                <details style={{ marginTop: '2rem' }}>
                    <summary>API Response Debug</summary>
                    <pre style={{ background: '#000', padding: '1rem', overflow: 'auto', fontSize: '0.75rem' }}>
                        {JSON.stringify(orderResult, null, 2)}
                    </pre>
                </details>
            </div>
        );
    }

    if (!cart || !cart.items || cart.items.length === 0) {
        return (
            <div className="page container">
                <div className="empty">Cart is empty. Add items first.</div>
            </div>
        );
    }

    return (
        <div className="page container">
            <h2>Checkout</h2>

            {error && <div className="error">Error: {error}</div>}

            <div className="two-col">
                {/* Order Items */}
                <div className="card">
                    <h3>Order Items</h3>
                    <table>
                        <thead>
                            <tr>
                                <th>Product</th>
                                <th>Qty</th>
                                <th>Price</th>
                                <th>Subtotal</th>
                            </tr>
                        </thead>
                        <tbody>
                            {cart.items.map(item => (
                                <tr key={item.id}>
                                    <td>{item.product_name}</td>
                                    <td>{item.quantity}</td>
                                    <td>${item.product_price}</td>
                                    <td>${item.subtotal?.toFixed(2)}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>

                {/* Order Summary */}
                <div className="card">
                    <h3>Order Summary</h3>
                    <table>
                        <tbody>
                            <tr>
                                <th>Subtotal</th>
                                <td>${cart.subtotal?.toFixed(2)}</td>
                            </tr>
                            <tr>
                                <th>Shipping</th>
                                <td>${cart.shipping?.toFixed(2)}</td>
                            </tr>
                            <tr style={{ fontWeight: 'bold', fontSize: '1.25rem' }}>
                                <th>Total</th>
                                <td>${cart.total?.toFixed(2)}</td>
                            </tr>
                        </tbody>
                    </table>

                    <button
                        className="primary"
                        style={{ width: '100%', marginTop: '1rem' }}
                        onClick={handleSubmitOrder}
                        disabled={submitting}
                    >
                        {submitting ? 'Creating Order...' : 'Place Order'}
                    </button>
                </div>
            </div>
        </div>
    );
}
