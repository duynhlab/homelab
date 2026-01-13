import { Link } from 'react-router-dom';
import PlaceholderImage from '../common/PlaceholderImage';

/**
 * ProductCard Component
 * Domain component - NO API calls
 * Receives product data as props
 */
export default function ProductCard({ product }) {
    return (
        <Link to={`/products/${product.id}`} className="product-card">
            <div className="product-image">
                <PlaceholderImage size="small" />
            </div>
            <div className="product-info">
                <h3 className="product-name">{product.name}</h3>
                <p className="product-price">${product.price}</p>
            </div>
        </Link>
    );
}
