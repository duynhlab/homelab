import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getUserProfile, updateProfile } from '../../api/userApi';
import { useToast } from '../../components/common/ToastProvider';
import './ProfilePage.css';

/**
 * ProfilePage Component
 * Allows users to view and edit their profile
 * Uses GET /api/v1/users/profile and PUT /api/v1/users/profile
 */
function ProfilePage() {
    const navigate = useNavigate();
    const { showToast } = useToast();
    const [profile, setProfile] = useState(null);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [editMode, setEditMode] = useState(false);
    const [formData, setFormData] = useState({
        name: '',
        phone: ''
    });

    useEffect(() => {
        // Check if user is authenticated
        const token = localStorage.getItem('authToken');
        if (!token) {
            navigate('/login');
            return;
        }

        fetchProfile();
    }, [navigate]);

    const fetchProfile = async () => {
        try {
            setLoading(true);
            const data = await getUserProfile();
            setProfile(data);
            setFormData({
                name: data.name || '',
                phone: data.phone || ''
            });
        } catch (error) {
            console.error('Failed to fetch profile:', error);
            showToast('Failed to load profile', 'error');
        } finally {
            setLoading(false);
        }
    };

    const handleInputChange = (e) => {
        const { name, value } = e.target;
        setFormData(prev => ({
            ...prev,
            [name]: value
        }));
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        try {
            setSaving(true);
            const updated = await updateProfile(formData);
            setProfile({ ...profile, ...updated });
            setEditMode(false);
            showToast('Profile updated successfully!', 'success');
        } catch (error) {
            console.error('Failed to update profile:', error);
            showToast('Failed to update profile', 'error');
        } finally {
            setSaving(false);
        }
    };

    const handleCancel = () => {
        setFormData({
            name: profile?.name || '',
            phone: profile?.phone || ''
        });
        setEditMode(false);
    };

    if (loading) {
        return (
            <div className="profile-page">
                <h1>My Profile</h1>
                <div className="profile-card">
                    <p>Loading profile...</p>
                </div>
            </div>
        );
    }

    return (
        <div className="profile-page">
            <h1>My Profile</h1>

            <div className="profile-card">
                {!editMode ? (
                    <div className="profile-view">
                        <div className="profile-field">
                            <label>User ID</label>
                            <span>{profile?.id || 'N/A'}</span>
                        </div>
                        <div className="profile-field">
                            <label>Username</label>
                            <span>{profile?.username || 'N/A'}</span>
                        </div>
                        <div className="profile-field">
                            <label>Email</label>
                            <span>{profile?.email || 'N/A'}</span>
                        </div>
                        <div className="profile-field">
                            <label>Name</label>
                            <span>{profile?.name || 'Not set'}</span>
                        </div>
                        <div className="profile-field">
                            <label>Phone</label>
                            <span>{profile?.phone || 'Not set'}</span>
                        </div>

                        <button 
                            className="btn btn-primary"
                            onClick={() => setEditMode(true)}
                        >
                            Edit Profile
                        </button>
                    </div>
                ) : (
                    <form onSubmit={handleSubmit} className="profile-form">
                        <div className="form-group">
                            <label htmlFor="name">Name</label>
                            <input
                                type="text"
                                id="name"
                                name="name"
                                value={formData.name}
                                onChange={handleInputChange}
                                placeholder="Enter your full name"
                            />
                        </div>

                        <div className="form-group">
                            <label htmlFor="phone">Phone</label>
                            <input
                                type="tel"
                                id="phone"
                                name="phone"
                                value={formData.phone}
                                onChange={handleInputChange}
                                placeholder="Enter your phone number"
                            />
                        </div>

                        <div className="form-actions">
                            <button 
                                type="button" 
                                className="btn btn-secondary"
                                onClick={handleCancel}
                                disabled={saving}
                            >
                                Cancel
                            </button>
                            <button 
                                type="submit" 
                                className="btn btn-primary"
                                disabled={saving}
                            >
                                {saving ? 'Saving...' : 'Save Changes'}
                            </button>
                        </div>
                    </form>
                )}
            </div>
        </div>
    );
}

export default ProfilePage;
