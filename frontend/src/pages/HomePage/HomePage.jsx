import { useState, useEffect } from 'react';
import ProductGrid from '../../components/domain/ProductGrid';
import { GridSkeleton } from '../../components/common/Skeleton';
import EmptyState from '../../components/common/EmptyState';
import ApiError from '../../components/common/ApiError';
import { getProducts } from '../../api/productApi';

/**
 * HomePage - Product Catalog
 * API: GET /api/v1/products
 * 
 * Responsibilities:
 * - Fetch products from API
 * - Handle loading/error/empty states
 * - Pass data to domain components
 */
export default function HomePage() {
    const [products, setProducts] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        async function fetchProducts() {
            setLoading(true);
            setError(null);
            try {
                const result = await getProducts();
                setProducts(Array.isArray(result) ? result : []);
                console.log('[API] GET /products:', result);
            } catch (err) {
                setError(err.message);
                console.error('[API ERROR] GET /products:', err);
            } finally {
                setLoading(false);
            }
        }
        fetchProducts();
    }, []);

    return (
        <div className="page container">
            <h2>Products</h2>
            <p className="api-label">API: GET /api/v1/products • {products.length} items</p>

            {/* Loading State */}
            {loading && <GridSkeleton count={8} />}

            {/* Error State */}
            {!loading && error && (
                <ApiError error={error} endpoint="GET /api/v1/products" />
            )}

            {/* Empty State */}
            {!loading && !error && products.length === 0 && (
                <EmptyState message="No products available" icon="📦" />
            )}

            {/* Success State */}
            {!loading && !error && products.length > 0 && (
                <ProductGrid products={products} />
            )}

            {/* API Debug */}
            <details className="api-debug">
                <summary>API Response</summary>
                <pre>{JSON.stringify(products, null, 2)}</pre>
            </details>
        </div>
    );
}
