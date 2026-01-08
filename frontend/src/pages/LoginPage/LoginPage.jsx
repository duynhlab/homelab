import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { login, register } from '../../api/authApi';

/**
 * Login Page - Auth APIs
 * POST /api/v1/auth/login
 * POST /api/v1/auth/register
 */
export default function LoginPage() {
    const navigate = useNavigate();
    const [mode, setMode] = useState('login'); // 'login' or 'register'
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [success, setSuccess] = useState(null);

    const [form, setForm] = useState({
        username: '',
        email: '',
        password: ''
    });

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);
        setError(null);
        setSuccess(null);

        try {
            let result;
            if (mode === 'login') {
                result = await login(form.username, form.password);
                console.log('[API] POST /auth/login:', result);
            } else {
                result = await register(form.username, form.email, form.password);
                console.log('[API] POST /auth/register:', result);
            }

            // Store token
            if (result.token) {
                localStorage.setItem('authToken', result.token);
            }

            setSuccess(`${mode === 'login' ? 'Login' : 'Registration'} successful!`);

            // Redirect after success
            setTimeout(() => navigate('/'), 1000);
        } catch (err) {
            setError(err.message);
            console.error('[API ERROR]', err);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="page container" style={{ maxWidth: '400px' }}>
            <div className="card">
                <h2>{mode === 'login' ? 'Login' : 'Register'}</h2>

                {error && <div className="error">{error}</div>}
                {success && <div className="success">{success}</div>}

                <form onSubmit={handleSubmit}>
                    <div className="form-group">
                        <label>Username</label>
                        <input
                            type="text"
                            value={form.username}
                            onChange={(e) => setForm({ ...form, username: e.target.value })}
                            required
                        />
                    </div>

                    {mode === 'register' && (
                        <div className="form-group">
                            <label>Email</label>
                            <input
                                type="email"
                                value={form.email}
                                onChange={(e) => setForm({ ...form, email: e.target.value })}
                                required
                            />
                        </div>
                    )}

                    <div className="form-group">
                        <label>Password</label>
                        <input
                            type="password"
                            value={form.password}
                            onChange={(e) => setForm({ ...form, password: e.target.value })}
                            required
                        />
                    </div>

                    <button type="submit" className="primary" style={{ width: '100%' }} disabled={loading}>
                        {loading ? 'Please wait...' : (mode === 'login' ? 'Login' : 'Register')}
                    </button>
                </form>

                <div style={{ marginTop: '1rem', textAlign: 'center' }}>
                    {mode === 'login' ? (
                        <p>
                            Don't have an account?{' '}
                            <button onClick={() => setMode('register')}>Register</button>
                        </p>
                    ) : (
                        <p>
                            Already have an account?{' '}
                            <button onClick={() => setMode('login')}>Login</button>
                        </p>
                    )}
                </div>

                <Link to="/" style={{ display: 'block', marginTop: '1rem', textAlign: 'center' }}>
                    ← Back to Shop
                </Link>
            </div>
        </div>
    );
}
