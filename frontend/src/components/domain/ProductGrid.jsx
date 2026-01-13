import ProductCard from './ProductCard';

/**
 * ProductGrid Component
 * Domain component - NO API calls
 * Receives products array as props
 */
export default function ProductGrid({ products }) {
    return (
        <div className="product-grid">
            {products.map(product => (
                <ProductCard key={product.id} product={product} />
            ))}
        </div>
    );
}
