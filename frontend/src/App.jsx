import { useState, useEffect, lazy, Suspense } from 'react';
import { Routes, Route, Link, useNavigate } from 'react-router-dom';
import useSWR from 'swr';
import { getCartCount } from './api/cartApi';
import Footer from './components/common/Footer';
import { GridSkeleton } from './components/common/Skeleton';

// Code splitting: Lazy load pages for better initial bundle size
const HomePage = lazy(() => import('./pages/HomePage/HomePage'));
const ProductDetailPage = lazy(() => import('./pages/ProductDetailPage/ProductDetailPage'));
const CartPage = lazy(() => import('./pages/CartPage/CartPage'));
const CheckoutPage = lazy(() => import('./pages/CheckoutPage/CheckoutPage'));
const OrdersPage = lazy(() => import('./pages/OrdersPage/OrdersPage'));
const NotificationPage = lazy(() => import('./pages/NotificationPage/NotificationPage'));
const ProfilePage = lazy(() => import('./pages/ProfilePage/ProfilePage'));
const LoginPage = lazy(() => import('./pages/LoginPage/LoginPage'));

/**
 * App Component
 * Proper layout: Header → Main (flex:1) → Footer
 * Uses GET /api/v1/cart/count for badge with SWR for smart revalidation
 */
function App() {
    const navigate = useNavigate();
    const [isAuthenticated, setIsAuthenticated] = useState(false);

    // SWR for cart count - automatic deduplication, caching, and smart revalidation
    // Only fetches when authenticated, revalidates on focus/reconnect
    const { data: cartData } = useSWR(
        isAuthenticated ? 'cart-count' : null, // Only fetch when authenticated
        getCartCount,
        {
            refreshInterval: 10000, // Poll every 10s (reduced from 5s)
            revalidateOnFocus: true, // Refresh when user returns to tab
            revalidateOnReconnect: true,
            dedupingInterval: 2000, // Dedupe requests within 2s
        }
    );

    const cartCount = cartData?.count || 0;

    const checkAuth = () => {
        const token = localStorage.getItem('authToken');
        setIsAuthenticated(!!token);
    };

    const handleLogout = () => {
        localStorage.removeItem('authToken');
        localStorage.removeItem('authUser');
        setIsAuthenticated(false);
        navigate('/login');
    };

    useEffect(() => {
        checkAuth();
        // Listen for storage changes (e.g., login/logout in other tabs or from LoginPage)
        const handleStorage = () => checkAuth();
        window.addEventListener('storage', handleStorage);
        return () => {
            window.removeEventListener('storage', handleStorage);
        };
    }, []);

    return (
        <div className="app">
            {/* Header */}
            <header className="header">
                <h1>
                    <Link to="/" style={{ color: 'inherit', textDecoration: 'none' }}>
                        🛒 Shop
                    </Link>
                </h1>
                <nav>
                    {isAuthenticated && (
                        <>
                            <Link to="/orders">Orders</Link>
                            <Link to="/notifications">Notifications</Link>
                            <Link to="/profile">Profile</Link>
                            <Link to="/cart">
                                Cart {cartCount > 0 && <span className="cart-badge">{cartCount}</span>}
                            </Link>
                        </>
                    )}
                    {isAuthenticated ? (
                        <button
                            className="btn-logout"
                            onClick={handleLogout}
                        >
                            Logout
                        </button>
                    ) : (
                        <Link to="/login">Login</Link>
                    )}
                </nav>
            </header>

            {/* Main Content - flex:1 pushes footer down */}
            <main className="app-main">
                <Suspense fallback={<GridSkeleton count={8} />}>
                    <Routes>
                        <Route path="/" element={<HomePage />} />
                        <Route path="/products/:id" element={<ProductDetailPage />} />
                        <Route path="/cart" element={<CartPage />} />
                        <Route path="/checkout" element={<CheckoutPage />} />
                        <Route path="/orders" element={<OrdersPage />} />
                        <Route path="/notifications" element={<NotificationPage />} />
                        <Route path="/profile" element={<ProfilePage />} />
                        <Route path="/login" element={<LoginPage />} />
                    </Routes>
                </Suspense>
            </main>

            {/* Footer - always at bottom */}
            <Footer />
        </div>
    );
}

export default App;
