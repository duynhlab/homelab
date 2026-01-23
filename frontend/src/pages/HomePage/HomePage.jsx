import ProductGrid from '../../components/domain/ProductGrid';
import { GridSkeleton } from '../../components/common/Skeleton';
import EmptyState from '../../components/common/EmptyState';
import ApiError from '../../components/common/ApiError';
import { useProducts } from '../../hooks/useProducts';

/**
 * HomePage - Product Catalog
 * API: GET /api/v1/products
 * 
 * Responsibilities:
 * - Fetch products from API (using useProducts hook with SWR)
 * - Handle loading/error/empty states
 * - Pass data to domain components
 */
export default function HomePage() {
    const { products, loading, error } = useProducts();

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
