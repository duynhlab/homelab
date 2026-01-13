import { useState, useEffect } from 'react';
import { getProducts } from '../api/productApi';

/**
 * Custom hook for fetching products
 * NOTE: No filter support - API doesn't have search/filter
 */
export function useProducts() {
    const [products, setProducts] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        async function fetchProducts() {
            setLoading(true);
            setError(null);
            try {
                const data = await getProducts();
                setProducts(Array.isArray(data) ? data : []);
            } catch (err) {
                setError(err.message || 'Failed to load products');
                setProducts([]);
            } finally {
                setLoading(false);
            }
        }
        fetchProducts();
    }, []);

    return { products, loading, error };
}
