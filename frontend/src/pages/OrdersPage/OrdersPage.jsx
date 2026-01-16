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
        setShipment(null);
        try {
            const result = await getOrder(orderId);
            setSelectedOrder(result);
            console.log('[API] GET /orders/' + orderId + ':', result);

            // Try to fetch shipment for specific order IDs
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
            const trackingNumbers = {
                '1': '1Z999AA10123456784',
                '2': '9400111899223344556677',
                '4': '794612345678'
            };
            const trackingNumber = trackingNumbers[orderId];
            if (trackingNumber) {
                const result = await trackShipment(trackingNumber);
                setShipment(result);
                console.log('[API] GET /shipping/track:', result);
            }
        } catch (err) {
            console.error('[API ERROR] Shipment:', err);
        } finally {
            setShipmentLoading(false);
        }
    };

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

    return (
        <div className="page container">
            <h2>My Orders</h2>
            <p className="api-label">API: GET /api/v1/orders • {orders.length} orders</p>

            {/* Loading */}
            {loading && <div className="loading">Loading orders...</div>}

            {/* Error */}
            {!loading && error && <div className="error">Error: {error}</div>}

            {/* Content */}
            {!loading && !error && (
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
                            <div className="table-wrapper">
                                <table>
                                    <thead>
                                        <tr>
                                            <th>Order</th>
                                            <th>Status</th>
                                            <th>Total</th>
                                            <th className="hide-mobile">Date</th>
                                            <th></th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {orders.map(order => (
                                            <tr key={order.id}>
                                                <td>#{order.id}</td>
                                                <td>
                                                    <span style={{ color: getStatusColor(order.status) }}>
                                                        {order.status}
                                                    </span>
                                                </td>
                                                <td>${order.total?.toFixed(2)}</td>
                                                <td className="hide-mobile">{new Date(order.created_at).toLocaleDateString()}</td>
                                                <td>
                                                    <button onClick={() => handleViewOrder(order.id)}>
                                                        {orderLoading ? '...' : 'View'}
                                                    </button>
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </div>

                    {/* Order Details */}
                    <div className="card">
                        <h3>Order Details</h3>
                        {selectedOrder ? (
                            <>
                                <p><strong>Order #{selectedOrder.id}</strong></p>
                                <p>
                                    Status:{' '}
                                    <span style={{ color: getStatusColor(selectedOrder.status) }}>
                                        {selectedOrder.status}
                                    </span>
                                </p>
                                <p className="text-muted">
                                    {new Date(selectedOrder.created_at).toLocaleString()}
                                </p>

                                {/* Shipping Tracking */}
                                {shipmentLoading && (
                                    <div className="shipment-box">Loading tracking...</div>
                                )}
                                {shipment && (
                                    <div className="shipment-box">
                                        <strong>📦 Shipment Tracking</strong>
                                        <p>Carrier: {shipment.carrier}</p>
                                        <p>
                                            Status:{' '}
                                            <span style={{ color: getStatusColor(shipment.status) }}>
                                                {shipment.status.replace('_', ' ').toUpperCase()}
                                            </span>
                                        </p>
                                        <p>Tracking: {shipment.tracking_number}</p>
                                        <p>Est: {new Date(shipment.estimated_delivery).toLocaleDateString()}</p>
                                    </div>
                                )}

                                <h4>Items:</h4>
                                {selectedOrder.items?.map((item, i) => (
                                    <div key={i} className="order-item">
                                        {item.product_name} ×{item.quantity} = ${item.subtotal?.toFixed(2)}
                                    </div>
                                ))}

                                <table>
                                    <tbody>
                                        <tr><th>Subtotal</th><td>${selectedOrder.subtotal?.toFixed(2)}</td></tr>
                                        <tr><th>Shipping</th><td>${selectedOrder.shipping?.toFixed(2)}</td></tr>
                                        <tr><th><strong>Total</strong></th><td><strong>${selectedOrder.total?.toFixed(2)}</strong></td></tr>
                                    </tbody>
                                </table>

                                {/* API Debug */}
                                <details className="api-debug">
                                    <summary>API Response</summary>
                                    <pre>{JSON.stringify({ order: selectedOrder, shipment }, null, 2)}</pre>
                                </details>
                            </>
                        ) : (
                            <p className="text-muted">Select an order to view details</p>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
}
