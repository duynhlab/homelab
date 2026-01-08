import { useState, useEffect } from 'react';
import { Routes, Route, Link } from 'react-router-dom';
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
    const [cartCount, setCartCount] = useState(0);

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
        fetchCartCount();
        const interval = setInterval(fetchCartCount, 5000);
        return () => clearInterval(interval);
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
                    <Link to="/orders">Orders</Link>
                    <Link to="/cart">
                        Cart {cartCount > 0 && <span className="cart-badge">{cartCount}</span>}
                    </Link>
                    <Link to="/login">Login</Link>
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
