import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { getOrders, getOrder } from '../../api/orderApi';
import { trackShipment } from '../../api/shippingApi';

/**
 * Orders Page - List and view orders with shipping tracking
 * GET /api/v1/orders
 * GET /api/v1/orders/:id
 * GET /api/v1/shipping/track?tracking_number={number}
 */
export default function OrdersPage() {
    const [orders, setOrders] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [selectedOrder, setSelectedOrder] = useState(null);
    const [orderLoading, setOrderLoading] = useState(false);
    const [shipment, setShipment] = useState(null);
    const [shipmentLoading, setShipmentLoading] = useState(false);

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
        setShipment(null); // Reset shipment
        try {
            const result = await getOrder(orderId);
            setSelectedOrder(result);
            console.log('[API] GET /orders/' + orderId + ':', result);

            // Try to fetch shipment tracking if order has tracking number
            // Note: In real scenario, backend should return tracking_number with order
            // For demo, we'll try to fetch shipment for order IDs 1, 2, 4 (from seed data)
            if ([1, 2, 4].includes(parseInt(orderId))) {
                fetchShipmentForOrder(orderId);
            }
        } catch (err) {
            alert('Error: ' + err.message);
            console.error('[API ERROR]', err);
        } finally {
            setOrderLoading(false);
        }
    };

    const fetchShipmentForOrder = async (orderId) => {
        setShipmentLoading(true);
        try {
            // Map order IDs to tracking numbers from seed data
            const trackingNumbers = {
                '1': '1Z999AA10123456784',      // UPS, delivered
                '2': '9400111899223344556677',  // USPS, in_transit
                '4': '794612345678'             // FedEx, pending
            };

            const trackingNumber = trackingNumbers[orderId];
            if (trackingNumber) {
                const result = await trackShipment(trackingNumber);
                setShipment(result);
                console.log('[API] GET /shipping/track:', result);
            }
        } catch (err) {
            console.error('[API ERROR] Shipment:', err);
            // Don't show error, just no tracking info
        } finally {
            setShipmentLoading(false);
        }
    };

    // Get status badge color
    const getStatusColor = (status) => {
        const colors = {
            pending: '#ffa500',
            processing: '#2196F3',
            completed: '#4CAF50',
            shipped: '#9C27B0',
            delivered: '#4CAF50',
            in_transit: '#2196F3'
        };
        return colors[status] || '#888';
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
                                        <td>
                                            <span style={{
                                                color: getStatusColor(order.status),
                                                fontWeight: 'bold'
                                            }}>
                                                {order.status}
                                            </span>
                                        </td>
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
                            <p>
                                Status: {' '}
                                <span style={{
                                    color: getStatusColor(selectedOrder.status),
                                    fontWeight: 'bold'
                                }}>
                                    {selectedOrder.status}
                                </span>
                            </p>
                            <p>Created: {new Date(selectedOrder.created_at).toLocaleString()}</p>

                            {/* Shipping Tracking */}
                            {shipmentLoading ? (
                                <div style={{ padding: '1rem', background: '#f5f5f5', borderRadius: '8px', marginTop: '1rem' }}>
                                    <p>Loading tracking info...</p>
                                </div>
                            ) : shipment ? (
                                <div style={{
                                    padding: '1rem',
                                    background: '#f0f8ff',
                                    border: '2px solid #2196F3',
                                    borderRadius: '8px',
                                    marginTop: '1rem'
                                }}>
                                    <h4 style={{ margin: '0 0 0.5rem 0', color: '#2196F3' }}>📦 Shipment Tracking</h4>
                                    <p style={{ margin: '0.25rem 0' }}>
                                        <strong>Carrier:</strong> {shipment.carrier}
                                    </p>
                                    <p style={{ margin: '0.25rem 0' }}>
                                        <strong>Status:</strong> {' '}
                                        <span style={{
                                            color: getStatusColor(shipment.status),
                                            fontWeight: 'bold'
                                        }}>
                                            {shipment.status.replace('_', ' ').toUpperCase()}
                                        </span>
                                    </p>
                                    <p style={{ margin: '0.25rem 0' }}>
                                        <strong>Tracking #:</strong> {shipment.tracking_number}
                                    </p>
                                    <p style={{ margin: '0.25rem 0' }}>
                                        <strong>Estimated Delivery:</strong> {' '}
                                        {new Date(shipment.estimated_delivery).toLocaleDateString()}
                                    </p>
                                </div>
                            ) : null}

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
                                    {JSON.stringify({ order: selectedOrder, shipment }, null, 2)}
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
