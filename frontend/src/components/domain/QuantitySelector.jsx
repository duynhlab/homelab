import { useState } from 'react';

/**
 * QuantitySelector Component
 * Domain component - NO API calls
 * Controlled component - parent manages state
 */
export default function QuantitySelector({ quantity, onChange, min = 1 }) {
    const handleIncrement = () => onChange(quantity + 1);
    const handleDecrement = () => onChange(Math.max(min, quantity - 1));
    const handleChange = (e) => {
        const value = parseInt(e.target.value) || min;
        onChange(Math.max(min, value));
    };

    return (
        <div className="quantity-selector">
            <label>Quantity:</label>
            <button onClick={handleDecrement} disabled={quantity <= min}>
                −
            </button>
            <input
                type="number"
                value={quantity}
                onChange={handleChange}
                min={min}
            />
            <button onClick={handleIncrement}>
                +
            </button>
        </div>
    );
}
