/**
 * Mock Product Data
 * Follows exact API contract from API_REFERENCE.md
 */

export const MOCK_PRODUCTS = [
    {
        id: '1',
        name: 'Wireless Mouse',
        description: 'Ergonomic wireless mouse with long battery life',
        price: 29.99,
        category: 'Electronics'
    },
    {
        id: '2',
        name: 'Mechanical Keyboard',
        description: 'RGB mechanical gaming keyboard with Cherry MX switches',
        price: 79.99,
        category: 'Peripherals'
    },
    {
        id: '3',
        name: 'USB-C Hub',
        description: '7-in-1 USB-C hub with HDMI, USB 3.0, and SD card readers',
        price: 39.99,
        category: 'Accessories'
    },
    {
        id: '4',
        name: 'Laptop Stand',
        description: 'Adjustable aluminum laptop stand for better ergonomics',
        price: 44.99,
        category: 'Accessories'
    },
    {
        id: '5',
        name: 'Webcam HD',
        description: '1080p HD webcam with built-in microphone',
        price: 59.99,
        category: 'Electronics'
    },
    {
        id: '6',
        name: 'Monitor 24"',
        description: '24-inch Full HD IPS monitor with ultra-thin bezels',
        price: 149.99,
        category: 'Computers'
    },
    {
        id: '7',
        name: 'Gaming Headset',
        description: 'Surround sound gaming headset with noise cancellation',
        price: 89.99,
        category: 'Peripherals'
    },
    {
        id: '8',
        name: 'External SSD 1TB',
        description: 'Portable 1TB SSD with USB 3.1 Gen 2 interface',
        price: 99.99,
        category: 'Computers'
    }
];

/**
 * Get mock product details (aggregation endpoint structure)
 */
export function getMockProductDetails(id) {
    const product = MOCK_PRODUCTS.find(p => p.id === id);

    if (!product) {
        return null;
    }

    // Mock aggregation response structure
    return {
        product,
        stock: {
            available: true,
            quantity: Math.floor(Math.random() * 50) + 10
        },
        reviews: [],
        reviews_summary: {
            total: 0,
            average_rating: 0.0
        },
        related_products: MOCK_PRODUCTS
            .filter(p => p.id !== id && p.category === product.category)
            .slice(0, 3)
            .map(p => ({
                id: p.id,
                name: p.name,
                price: p.price
            }))
    };
}
