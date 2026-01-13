import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { getCart, updateCartItem, removeCartItem } from '../../api/cartApi';

/**
 * Cart Page - Full cart operations
 * GET /api/v1/cart
 * PATCH /api/v1/cart/items/:itemId
 * DELETE /api/v1/cart/items/:itemId
 */
export default function CartPage() {
    const [cart, setCart] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [actionLoading, setActionLoading] = useState(null);
    const [actionMessage, setActionMessage] = useState(null);

    const fetchCart = async () => {
        setLoading(true);
        setError(null);
        try {
            const result = await getCart();
            setCart(result);
            console.log('[API] GET /cart:', result);
        } catch (err) {
            setError(err.message);
            console.error('[API ERROR]', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchCart();
    }, []);

    const handleUpdateQuantity = async (itemId, newQuantity) => {
        if (newQuantity < 1) return;
        setActionLoading(itemId);
        setActionMessage(null);
        try {
            const result = await updateCartItem(itemId, newQuantity);
            console.log('[API] PATCH /cart/items/' + itemId + ':', result);
            setActionMessage({ type: 'success', text: 'Updated!' });
            fetchCart(); // Refresh cart
        } catch (err) {
            setActionMessage({ type: 'error', text: err.message });
            console.error('[API ERROR]', err);
        } finally {
            setActionLoading(null);
        }
    };

    const handleRemoveItem = async (itemId) => {
        setActionLoading(itemId);
        setActionMessage(null);
        try {
            const result = await removeCartItem(itemId);
            console.log('[API] DELETE /cart/items/' + itemId + ':', result);
            setActionMessage({ type: 'success', text: 'Removed!' });
            fetchCart(); // Refresh cart
        } catch (err) {
            setActionMessage({ type: 'error', text: err.message });
            console.error('[API ERROR]', err);
        } finally {
            setActionLoading(null);
        }
    };

    if (loading) return <div className="loading">Loading cart...</div>;
    if (error) return <div className="error">Error: {error}</div>;

    const items = cart?.items || [];

    return (
        <div className="page container">
            <h2>Shopping Cart</h2>

            {actionMessage && (
                <div className={actionMessage.type}>{actionMessage.text}</div>
            )}

            {items.length === 0 ? (
                <div className="empty">
                    <p>Your cart is empty</p>
                    <Link to="/">Browse Products</Link>
                </div>
            ) : (
                <div className="two-col">
                    {/* Cart Items */}
                    <div className="card">
                        <h3>Items ({cart.item_count})</h3>
                        {items.map(item => (
                            <div key={item.id} className="cart-item">
                                <div>
                                    <strong>{item.product_name}</strong>
                                    <p style={{ color: '#888' }}>${item.product_price} each</p>
                                </div>
                                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                    <button
                                        onClick={() => handleUpdateQuantity(item.id, item.quantity - 1)}
                                        disabled={actionLoading === item.id || item.quantity <= 1}
                                    >
                                        -
                                    </button>
                                    <span>{item.quantity}</span>
                                    <button
                                        onClick={() => handleUpdateQuantity(item.id, item.quantity + 1)}
                                        disabled={actionLoading === item.id}
                                    >
                                        +
                                    </button>
                                    <span style={{ marginLeft: '1rem' }}>${item.subtotal?.toFixed(2)}</span>
                                    <button
                                        className="danger"
                                        onClick={() => handleRemoveItem(item.id)}
                                        disabled={actionLoading === item.id}
                                    >
                                        Remove
                                    </button>
                                </div>
                            </div>
                        ))}
                    </div>

                    {/* Cart Summary */}
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
                                <tr style={{ fontWeight: 'bold' }}>
                                    <th>Total</th>
                                    <td>${cart.total?.toFixed(2)}</td>
                                </tr>
                            </tbody>
                        </table>
                        <Link to="/checkout">
                            <button className="primary" style={{ width: '100%', marginTop: '1rem' }}>
                                Proceed to Checkout
                            </button>
                        </Link>
                    </div>
                </div>
            )}

            {/* API Debug */}
            <details style={{ marginTop: '2rem' }}>
                <summary>API Response Debug</summary>
                <pre style={{ background: '#000', padding: '1rem', overflow: 'auto', fontSize: '0.75rem' }}>
                    {JSON.stringify(cart, null, 2)}
                </pre>
            </details>
        </div>
    );
}
