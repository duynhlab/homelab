import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { getOrders, getOrder } from '../../api/orderApi';

/**
 * Orders Page - List and view orders
 * GET /api/v1/orders
 * GET /api/v1/orders/:id
 */
export default function OrdersPage() {
    const [orders, setOrders] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [selectedOrder, setSelectedOrder] = useState(null);
    const [orderLoading, setOrderLoading] = useState(false);

    useEffect(() => {
        async function fetchOrders() {
            try {
                const result = await getOrders();
                setOrders(Array.isArray(result) ? result : []);
                console.log('[API] GET /orders:', result);
            } catch (err) {
                setError(err.message);
                console.error('[API ERROR]', err);
            } finally {
                setLoading(false);
            }
        }
        fetchOrders();
    }, []);

    const handleViewOrder = async (orderId) => {
        setOrderLoading(true);
        try {
            const result = await getOrder(orderId);
            setSelectedOrder(result);
            console.log('[API] GET /orders/' + orderId + ':', result);
        } catch (err) {
            alert('Error: ' + err.message);
            console.error('[API ERROR]', err);
        } finally {
            setOrderLoading(false);
        }
    };

    if (loading) return <div className="loading">Loading orders...</div>;
    if (error) return <div className="error">Error: {error}</div>;

    return (
        <div className="page container">
            <h2>My Orders</h2>

            <div className="two-col">
                {/* Orders List */}
                <div className="card">
                    <h3>Order History</h3>
                    {orders.length === 0 ? (
                        <div className="empty">
                            <p>No orders yet</p>
                            <Link to="/">Start Shopping</Link>
                        </div>
                    ) : (
                        <table>
                            <thead>
                                <tr>
                                    <th>Order ID</th>
                                    <th>Status</th>
                                    <th>Total</th>
                                    <th>Date</th>
                                    <th></th>
                                </tr>
                            </thead>
                            <tbody>
                                {orders.map(order => (
                                    <tr key={order.id}>
                                        <td>#{order.id}</td>
                                        <td>{order.status}</td>
                                        <td>${order.total?.toFixed(2)}</td>
                                        <td>{new Date(order.created_at).toLocaleDateString()}</td>
                                        <td>
                                            <button onClick={() => handleViewOrder(order.id)}>
                                                {orderLoading ? '...' : 'View'}
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    )}
                </div>

                {/* Order Details */}
                <div className="card">
                    <h3>Order Details</h3>
                    {selectedOrder ? (
                        <>
                            <p><strong>Order #{selectedOrder.id}</strong></p>
                            <p>Status: {selectedOrder.status}</p>
                            <p>Created: {new Date(selectedOrder.created_at).toLocaleString()}</p>

                            <h4 style={{ marginTop: '1rem' }}>Items:</h4>
                            {selectedOrder.items?.map((item, i) => (
                                <div key={i} style={{ padding: '0.5rem 0', borderBottom: '1px solid #333' }}>
                                    {item.product_name} x{item.quantity} = ${item.subtotal?.toFixed(2)}
                                </div>
                            ))}

                            <table style={{ marginTop: '1rem' }}>
                                <tbody>
                                    <tr><th>Subtotal</th><td>${selectedOrder.subtotal?.toFixed(2)}</td></tr>
                                    <tr><th>Shipping</th><td>${selectedOrder.shipping?.toFixed(2)}</td></tr>
                                    <tr style={{ fontWeight: 'bold' }}><th>Total</th><td>${selectedOrder.total?.toFixed(2)}</td></tr>
                                </tbody>
                            </table>

                            <details style={{ marginTop: '1rem' }}>
                                <summary>Raw API Response</summary>
                                <pre style={{ background: '#000', padding: '0.5rem', fontSize: '0.75rem', overflow: 'auto' }}>
                                    {JSON.stringify(selectedOrder, null, 2)}
                                </pre>
                            </details>
                        </>
                    ) : (
                        <p className="text-muted">Select an order to view details</p>
                    )}
                </div>
            </div>
        </div>
    );
}
