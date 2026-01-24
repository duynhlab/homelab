import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { getCart, updateCartItem, removeCartItem } from '../../api/cartApi';
import { useToast } from '../../components/common/ToastProvider';

/**
 * Cart Page - Full cart operations
 * GET /api/v1/cart
 * PATCH /api/v1/cart/items/:itemId
 * DELETE /api/v1/cart/items/:itemId
 */
export default function CartPage() {
    const navigate = useNavigate();
    const { notify } = useToast();
    const [cart, setCart] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [actionLoading, setActionLoading] = useState(null);

    // Check authentication
    const isAuthenticated = !!localStorage.getItem('authToken');

    const fetchCart = async () => {
        setLoading(true);
        setError(null);
        try {
            const result = await getCart();
            setCart(result);
            if (import.meta.env.DEV) {
                console.log('[API] GET /cart:', result);
            }
        } catch (err) {
            setError(err.message);
            if (import.meta.env.DEV) {
                console.error('[API ERROR]', err);
            }
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        // Only fetch cart if authenticated
        if (!isAuthenticated) {
            setLoading(false);
            return;
        }
        fetchCart();
    }, [isAuthenticated]);

    const handleUpdateQuantity = async (itemId, newQuantity) => {
        if (newQuantity < 1) return;
        setActionLoading(itemId);
        try {
            const result = await updateCartItem(itemId, newQuantity);
            if (import.meta.env.DEV) {
                console.log('[API] PATCH /cart/items/' + itemId + ':', result);
            }
            notify('success', 'Updated!');
            fetchCart();
        } catch (err) {
            notify('error', err.message);
            if (import.meta.env.DEV) {
                console.error('[API ERROR]', err);
            }
        } finally {
            setActionLoading(null);
        }
    };

    const handleRemoveItem = async (itemId) => {
        setActionLoading(itemId);
        try {
            const result = await removeCartItem(itemId);
            if (import.meta.env.DEV) {
                console.log('[API] DELETE /cart/items/' + itemId + ':', result);
            }
            notify('success', 'Removed!');
            fetchCart();
        } catch (err) {
            notify('error', err.message);
            if (import.meta.env.DEV) {
                console.error('[API ERROR]', err);
            }
        } finally {
            setActionLoading(null);
        }
    };

    const items = cart?.items || [];

    // Gated state for unauthenticated users
    if (!isAuthenticated) {
        return (
            <div className="page container">
                <h2>Shopping Cart</h2>
                <div className="empty" style={{ marginTop: '1rem' }}>
                    <p>You need to log in to view your cart.</p>
                    <div style={{ marginTop: '1rem', display: 'flex', gap: '0.5rem', justifyContent: 'center' }}>
                        <button className="primary" onClick={() => navigate('/login')}>
                            Login
                        </button>
                        <button onClick={() => navigate('/')}>
                            Continue Shopping
                        </button>
                    </div>
                </div>
            </div>
        );
    }

    return (
        <div className="page container">
            <h2>Shopping Cart</h2>
            <p className="api-label">API: GET /api/v1/cart</p>

            {/* Loading */}
            {loading && <div className="loading">Loading cart...</div>}

            {/* Error */}
            {!loading && error && <div className="error">Error: {error}</div>}

            {/* Empty */}
            {!loading && !error && items.length === 0 && (
                <div className="empty">
                    <p>Your cart is empty</p>
                    <Link to="/">Browse Products</Link>
                </div>
            )}

            {/* Cart Content */}
            {!loading && !error && items.length > 0 && (
                <div className="two-col">
                    {/* Cart Items */}
                    <div className="card">
                        <h3>Items ({cart.item_count})</h3>
                        {items.map(item => (
                            <div key={item.id} className="cart-item">
                                <div>
                                    <strong>{item.product_name}</strong>
                                    <p className="text-muted">${item.product_price} each</p>
                                </div>
                                <div className="cart-item-actions">
                                    <button
                                        onClick={() => handleUpdateQuantity(item.id, item.quantity - 1)}
                                        disabled={actionLoading === item.id || item.quantity <= 1}
                                    >−</button>
                                    <span>{item.quantity}</span>
                                    <button
                                        onClick={() => handleUpdateQuantity(item.id, item.quantity + 1)}
                                        disabled={actionLoading === item.id}
                                    >+</button>
                                    <span className="cart-item-subtotal">${item.subtotal?.toFixed(2)}</span>
                                    <button
                                        className="danger"
                                        onClick={() => handleRemoveItem(item.id)}
                                        disabled={actionLoading === item.id}
                                    >Remove</button>
                                </div>
                            </div>
                        ))}
                    </div>

                    {/* Cart Summary */}
                    <div className="card">
                        <h3>Order Summary</h3>
                        <table>
                            <tbody>
                                <tr><th>Subtotal</th><td>${cart.subtotal?.toFixed(2)}</td></tr>
                                <tr><th>Shipping</th><td>${cart.shipping?.toFixed(2)}</td></tr>
                                <tr><th><strong>Total</strong></th><td><strong>${cart.total?.toFixed(2)}</strong></td></tr>
                            </tbody>
                        </table>
                        <Link to="/checkout">
                            <button className="primary" style={{ width: '100%', marginTop: '0.75rem' }}>
                                Proceed to Checkout
                            </button>
                        </Link>
                    </div>
                </div>
            )}

            {/* API Debug */}
            <details className="api-debug">
                <summary>API Response</summary>
                <pre>{JSON.stringify(cart, null, 2)}</pre>
            </details>
        </div>
    );
}
