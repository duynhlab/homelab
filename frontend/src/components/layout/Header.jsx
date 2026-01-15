import { Link } from 'react-router-dom';
import './Header.css';

/**
 * Header Component
 * Site navigation with logo, nav links, and cart badge
 */
export default function Header({ cartCount = 0 }) {
    return (
        <header className="header glass">
            <div className="container">
                <nav className="header__nav">
                    {/* Logo */}
                    <Link to="/" className="header__logo">
                        <span className="header__logo-icon">🛒</span>
                        <span className="header__logo-text">Shop</span>
                    </Link>

                    {/* Navigation Links */}
                    <ul className="header__links">
                        <li>
                            <Link to="/" className="header__link">Products</Link>
                        </li>
                        <li>
                            <Link to="/orders" className="header__link">Orders</Link>
                        </li>
                    </ul>

                    {/* Right Section - Cart & User */}
                    <div className="header__actions">
                        {/* Cart Button */}
                        <Link to="/cart" className="header__cart">
                            <span className="header__cart-icon">🛒</span>
                            {cartCount > 0 && (
                                <span className="header__cart-badge">{cartCount}</span>
                            )}
                        </Link>

                        {/* User Menu (placeholder) */}
                        <Link to="/login" className="header__user">
                            <span className="header__user-icon">👤</span>
                        </Link>
                    </div>
                </nav>
            </div>
        </header>
    );
}
