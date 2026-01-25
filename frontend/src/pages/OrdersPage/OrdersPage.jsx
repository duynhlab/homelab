import { useState, useMemo, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { getOrders, getOrderDetails } from '../../api/orderApi';
import { useAuth } from '../../hooks/useAuth';
import { useApiQuery } from '../../hooks/useApiQuery';
import { useToast } from '../../components/common/ToastProvider';
import PageHeader from '../../components/common/PageHeader';
import LoadingState from '../../components/common/LoadingState';
import EmptyState from '../../components/common/EmptyState';
import ApiDebug from '../../components/common/ApiDebug';

/**
 * Orders Page - List and view orders with shipping tracking
 * API: GET /api/v1/orders - List all orders
 * API: GET /api/v1/orders/:id/details - Get order with shipment (aggregation)
 * 
 * Uses aggregation endpoint for strict 3-layer compliance
 */
export default function OrdersPage() {
    const navigate = useNavigate();
    const { notify } = useToast();
    const { isAuthenticated, requireAuth } = useAuth();

    // Selected order state (for details panel)
    const [selectedOrderId, setSelectedOrderId] = useState(null);
    const [selectedOrderData, setSelectedOrderData] = useState(null);
    const [orderDetailsLoading, setOrderDetailsLoading] = useState(false);

    // Auth guard effect
    useEffect(() => {
        // Don't redirect, just show login prompt
    }, []);

    // Fetch orders list using shared hook
    const { data: orders, loading, error } = useApiQuery(
        isAuthenticated ? 'orders' : null,
        getOrders
    );

    const ordersList = useMemo(() => orders || [], [orders]);

    // Handle viewing order details (uses aggregation endpoint)
    const handleViewOrder = async (orderId) => {
        setSelectedOrderId(orderId);
        setOrderDetailsLoading(true);
        setSelectedOrderData(null);

        try {
            const result = await getOrderDetails(orderId);
            setSelectedOrderData(result);
            if (import.meta.env.DEV) {
                console.log('[API] GET /orders/' + orderId + '/details:', result);
            }
        } catch (err) {
            notify('error', 'Failed to load order details');
            if (import.meta.env.DEV) {
                console.error('[API ERROR]', err);
            }
        } finally {
            setOrderDetailsLoading(false);
        }
    };

    const getStatusColor = (status) => {
        const colors = {
            pending: 'var(--warning)',
            processing: 'var(--info)',
            completed: 'var(--success)',
            shipped: 'var(--accent)',
            delivered: 'var(--success)',
            in_transit: 'var(--info)',
        };
        return colors[status] || 'var(--text-muted)';
    };

    // Auth gate
    if (!isAuthenticated) {
        return (
            <div className="page container">
                <PageHeader title="My Orders" backLink="/" backText="← Back to Home" />
                <EmptyState message="Please log in to view your orders" icon="🔒" />
                <div style={{ textAlign: 'center', marginTop: '1rem' }}>
                    <button className="primary" onClick={() => navigate('/login?returnTo=/orders')}>
                        Login
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div className="page container">
            <PageHeader 
                title="My Orders" 
                backLink="/" 
                backText="← Back to Home"
                apiLabel={`API: GET /api/v1/orders • ${ordersList.length} orders`}
            />

            {/* Loading */}
            {loading && <LoadingState message="Loading orders..." variant="list" count={3} />}

            {/* Error */}
            {!loading && error && (
                <div className="error">Error: {error}</div>
            )}

            {/* Content */}
            {!loading && !error && (
                <div className="two-col">
                    {/* Orders List */}
                    <div className="card orders-history">
                        <h3>Order History</h3>
                        {ordersList.length === 0 ? (
                            <EmptyState message="No orders yet" icon="📦">
                                <Link to="/">Start Shopping</Link>
                            </EmptyState>
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
                                        {ordersList.map(order => (
                                            <tr key={order.id}>
                                                <td>#{order.id}</td>
                                                <td>
                                                    <span style={{ color: getStatusColor(order.status) }}>
                                                        {order.status}
                                                    </span>
                                                </td>
                                                <td>${order.total?.toFixed(2)}</td>
                                                <td className="hide-mobile">
                                                    {new Date(order.created_at).toLocaleDateString()}
                                                </td>
                                                <td>
                                                    <button 
                                                        onClick={() => handleViewOrder(order.id)}
                                                        disabled={orderDetailsLoading && selectedOrderId === order.id}
                                                    >
                                                        {orderDetailsLoading && selectedOrderId === order.id ? '...' : 'View'}
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
                    <div className="card order-details">
                        <h3>Order Details</h3>
                        {orderDetailsLoading && (
                            <LoadingState message="Loading order details..." />
                        )}
                        
                        {!orderDetailsLoading && selectedOrderData ? (
                            <OrderDetailsPanel 
                                order={selectedOrderData.order} 
                                shipment={selectedOrderData.shipment}
                                getStatusColor={getStatusColor}
                            />
                        ) : !orderDetailsLoading && (
                            <p className="text-muted">Select an order to view details</p>
                        )}
                    </div>
                </div>
            )}

            {/* API Debug */}
            <ApiDebug data={{ orders: ordersList, selectedOrderData }} label="Orders API Response" />
        </div>
    );
}

// Separate component for order details panel
function OrderDetailsPanel({ order, shipment, getStatusColor }) {
    if (!order) return null;

    return (
        <>
            <p><strong>Order #{order.id}</strong></p>
            <p>
                Status:{' '}
                <span style={{ color: getStatusColor(order.status) }}>
                    {order.status}
                </span>
            </p>
            <p className="text-muted">
                {new Date(order.created_at).toLocaleString()}
            </p>

            {/* Shipping Tracking - from aggregation endpoint */}
            {shipment && (
                <div className="shipment-box">
                    <strong>📦 Shipment Tracking</strong>
                    <p>Carrier: {shipment.carrier || 'N/A'}</p>
                    <p>
                        Status:{' '}
                        <span style={{ color: getStatusColor(shipment.status) }}>
                            {shipment.status?.replace('_', ' ').toUpperCase()}
                        </span>
                    </p>
                    <p>Tracking: {shipment.tracking_number}</p>
                    {shipment.estimated_delivery && (
                        <p>Est: {new Date(shipment.estimated_delivery).toLocaleDateString()}</p>
                    )}
                </div>
            )}
            {!shipment && order.status === 'shipped' && (
                <div className="shipment-box">
                    <p className="text-muted">Shipment info not available</p>
                </div>
            )}

            <h4>Items:</h4>
            {order.items?.map((item, i) => (
                <div key={i} className="order-item">
                    {item.product_name} ×{item.quantity} = ${item.subtotal?.toFixed(2)}
                </div>
            ))}

            <table>
                <tbody>
                    <tr><th>Subtotal</th><td>${order.subtotal?.toFixed(2)}</td></tr>
                    <tr><th>Shipping</th><td>${order.shipping?.toFixed(2)}</td></tr>
                    <tr><th><strong>Total</strong></th><td><strong>${order.total?.toFixed(2)}</strong></td></tr>
                </tbody>
            </table>
        </>
    );
}
