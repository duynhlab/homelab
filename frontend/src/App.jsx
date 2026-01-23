import { useState, useEffect } from 'react';
import { Routes, Route, Link, useNavigate } from 'react-router-dom';
import { getCartCount } from './api/cartApi';
import Footer from './components/common/Footer';

// Pages
import HomePage from './pages/HomePage/HomePage';
import ProductDetailPage from './pages/ProductDetailPage/ProductDetailPage';
import CartPage from './pages/CartPage/CartPage';
import CheckoutPage from './pages/CheckoutPage/CheckoutPage';
import OrdersPage from './pages/OrdersPage/OrdersPage';
import LoginPage from './pages/LoginPage/LoginPage';

/**
 * App Component
 * Proper layout: Header → Main (flex:1) → Footer
 * Uses GET /api/v1/cart/count for badge
 */
function App() {
    const navigate = useNavigate();
    const [cartCount, setCartCount] = useState(0);
    const [isAuthenticated, setIsAuthenticated] = useState(false);

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

    const fetchCartCount = async () => {
        try {
            const result = await getCartCount();
            setCartCount(result.count || 0);
            console.log('[API] GET /cart/count:', result);
        } catch (err) {
            console.error('[API ERROR] cart/count:', err.message);
        }
    };

    useEffect(() => {
        checkAuth();
        fetchCartCount();
        const interval = setInterval(fetchCartCount, 5000);
        // Listen for storage changes (e.g., login/logout in other tabs or from LoginPage)
        const handleStorage = () => checkAuth();
        window.addEventListener('storage', handleStorage);
        return () => {
            clearInterval(interval);
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
                    <Link to="/">Products</Link>
                    {isAuthenticated && (
                        <>
                            <Link to="/orders">Orders</Link>
                            <Link to="/cart">
                                Cart {cartCount > 0 && <span className="cart-badge">{cartCount}</span>}
                            </Link>
                        </>
                    )}
                    {isAuthenticated ? (
                        <button
                            onClick={handleLogout}
                            style={{
                                background: 'none',
                                border: 'none',
                                color: 'var(--accent)',
                                cursor: 'pointer',
                                padding: 0,
                                fontSize: 'inherit'
                            }}
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
                <Routes>
                    <Route path="/" element={<HomePage />} />
                    <Route path="/products/:id" element={<ProductDetailPage />} />
                    <Route path="/cart" element={<CartPage />} />
                    <Route path="/checkout" element={<CheckoutPage />} />
                    <Route path="/orders" element={<OrdersPage />} />
                    <Route path="/login" element={<LoginPage />} />
                </Routes>
            </main>

            {/* Footer - always at bottom */}
            <Footer />
        </div>
    );
}

export default App;
