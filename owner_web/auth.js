document.addEventListener('DOMContentLoaded', () => {
    // Elements
    const loginWrapper = document.getElementById('login-wrapper');
    const registerWrapper = document.getElementById('register-wrapper');
    const goToRegisterBtn = document.getElementById('go-to-register');
    const goToLoginBtn = document.getElementById('go-to-login');
    
    const loginForm = document.getElementById('login-form');
    const registerForm = document.getElementById('register-form');

    // Toggle Forms
    goToRegisterBtn.addEventListener('click', () => {
        loginWrapper.style.display = 'none';
        registerWrapper.style.display = 'block';
    });

    goToLoginBtn.addEventListener('click', () => {
        registerWrapper.style.display = 'none';
        loginWrapper.style.display = 'block';
    });

    // Handle Login Submission
loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const email = document.getElementById('login-email').value;
    const password = document.getElementById('login-password').value;

    
    if (!email || !password) {
        alert('fill up all fields.');
        return;
    }

    try {
       
        const response = await fetch('http://localhost:3000/api/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ email, password })
        });

        const result = await response.json();

        if (response.ok) {
            console.log('Login successful:', result);
            localStorage.setItem('business_name', result.user.business_name);
            localStorage.setItem('owner_id', result.user.id);
            localStorage.setItem('study_spot_id', result.user.study_spot_id || '');
            const profilePictureUrl = result.user.profile_picture_url || '';
            if (profilePictureUrl) {
                localStorage.setItem('profile_picture_url', profilePictureUrl);
            } else {
                localStorage.removeItem('profile_picture_url');
            }
            window.location.href = 'index.html';
        } else {
           
            alert('Login Failed: ' + result.error);
        }
    } catch (err) {
        console.error('Server connection error:', err);
        alert('Internal Server Error.');
    }
});

    // Elements for Modal
    const shopDetailsModal = document.getElementById('shop-details-modal');
    const shopDetailsForm = document.getElementById('shop-details-form');
    const closeModalBtn = document.getElementById('close-modal-btn');

    // Handle initial Registration form (Step 1)
    registerForm.addEventListener('submit', (e) => {
        e.preventDefault();
        // Show Shop Details Modal
        shopDetailsModal.classList.add('active');
    });

    // Close Modal
    closeModalBtn.addEventListener('click', () => {
        shopDetailsModal.classList.remove('active');
    });

    // Close on outside click
    shopDetailsModal.addEventListener('click', (e) => {
        if (e.target === shopDetailsModal) {
            shopDetailsModal.classList.remove('active');
        }
    });

    // Handle Final Registration Submission (Modal)
    shopDetailsForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const ownerData = {
        email: document.getElementById('reg-contact').value,
        password: document.getElementById('reg-password').value,
        business_name: document.getElementById('reg-shop-name').value,
        total_seats: parseInt(document.getElementById('reg-seats').value)
    };

    try {
        const response = await fetch('http://localhost:3000/api/register-owner', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(ownerData)
        });

        const result = await response.json();
        if (response.ok) {
            alert('Registration Successful!');
            window.location.href = 'index.html';
        } else {
            alert('Error: ' + result.error);
        }
    } catch (err) {
        console.error('Connection failed:', err);
    }
});

    // Simulated Scanning Interaction
    const scanBtn = document.getElementById('scan-permit-btn');
    const permitInput = document.getElementById('reg-permit');
    const verificationBox = document.querySelector('.verification-box');
    const verificationStatus = document.getElementById('verification-status');
    const statusText = document.getElementById('status-text');
    const extractedData = document.getElementById('extracted-data');
    
    function startVerification() {
        if (!scanBtn) return;
        
        const file = permitInput.files[0];
        const fileName = file ? file.name.toLowerCase() : '';
        const isLikelyPermit = ['permit', 'business', 'mayor', 'license', 'legal', 'doc'].some(kw => fileName.includes(kw));

        // Reset states
        verificationStatus.style.display = 'block';
        extractedData.style.display = 'none';
        statusText.innerText = 'Analyzing Authenticity...';
        statusText.parentElement.classList.remove('verified', 'failed');
        statusText.previousElementSibling.className = 'fa-solid fa-circle-notch fa-spin';
        verificationBox.classList.remove('failed');
        verificationBox.style.backgroundColor = '#F0F7FF';
        verificationBox.style.borderStyle = 'dashed';
        verificationBox.style.borderColor = 'var(--primary-color)';
        verificationBox.querySelector('.verification-icon').className = 'fa-solid fa-file-shield verification-icon';
        verificationBox.querySelector('.verification-icon').style.color = 'var(--primary-color)';
        
        scanBtn.disabled = true;
        scanBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Analyzing...';
        verificationBox.classList.add('scanning-active');
        verificationBox.classList.add('pulse');
        
        // Phase 1: Security Seal Check
        setTimeout(() => {
            statusText.innerText = 'Checking Security Seals & Metadata...';
        }, 1500);

        // Phase 2: Database Cross-Reference
        setTimeout(() => {
            statusText.innerText = 'Cross-referencing with Business Registry...';
        }, 3000);

        // Phase 3: Final Decision
        setTimeout(() => {
            verificationBox.classList.remove('scanning-active', 'pulse');
            
            if (isLikelyPermit) {
                // SUCCESS
                scanBtn.innerHTML = '<i class="fa-solid fa-check"></i> Authentic';
                scanBtn.classList.remove('btn-outline', 'btn-danger');
                scanBtn.classList.add('btn-primary');
                
                verificationBox.style.borderStyle = 'solid';
                verificationBox.style.backgroundColor = '#E8F5E9';
                verificationBox.querySelector('.verification-icon').style.color = '#2E7D32';
                verificationBox.querySelector('.verification-icon').className = 'fa-solid fa-circle-check verification-icon';
                
                statusText.innerText = 'Authenticity Verified';
                statusText.parentElement.classList.add('verified');
                statusText.previousElementSibling.className = 'fa-solid fa-shield-check';
                
                extractedData.style.display = 'grid';
                document.getElementById('mock-permit-id').innerText = 'BP-' + Math.floor(1000 + Math.random() * 9000) + '-DGS';
            } else {
                // FAILURE
                scanBtn.innerHTML = '<i class="fa-solid fa-xmark"></i> Rejected';
                scanBtn.disabled = false;
                scanBtn.classList.remove('btn-outline', 'btn-primary');
                scanBtn.classList.add('btn-danger'); 
                
                verificationBox.classList.add('failed');
                statusText.innerText = 'Verification Failed: Document Not Recognized';
                statusText.parentElement.classList.add('failed');
                statusText.previousElementSibling.className = 'fa-solid fa-circle-xmark';
                
                // Allow them to try again with a different file
                scanBtn.innerHTML = '<i class="fa-solid fa-rotate-right"></i> Retry';
            }
        }, 5000);
    }

    if (scanBtn) {
        scanBtn.addEventListener('click', startVerification);
    }

    if (permitInput) {
        permitInput.addEventListener('change', (e) => {
            if (e.target.files.length > 0) {
                startVerification();
            }
        });
    }
});