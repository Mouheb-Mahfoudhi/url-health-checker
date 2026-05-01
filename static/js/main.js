const form = document.getElementById('healthCheckForm');
const checkButton = document.getElementById('checkButton');
const loading = document.getElementById('loading');
const results = document.getElementById('results');
const errorMessage = document.getElementById('errorMessage');

form.addEventListener('submit', async (e) => {
    e.preventDefault();

    const url = document.getElementById('url').value.trim();

    if (!url) {
        showError('Please enter a URL');
        return;
    }

    // Show loading
    checkButton.disabled = true;
    loading.classList.add('show');
    results.classList.remove('show');
    errorMessage.classList.remove('show');

    try {
        const response = await fetch(`/health?url=${encodeURIComponent(url)}`);

        if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.detail || 'Failed to check website health');
        }

        const data = await response.json();
        displayResults(data);

    } catch (error) {
        showError(error.message);
    } finally {
        checkButton.disabled = false;
        loading.classList.remove('show');
    }
});

function displayResults(data) {
    const resultCard = document.getElementById('resultCard');
    const resultUrl = document.getElementById('resultUrl');
    const statusCode = document.getElementById('statusCode');
    const responseTime = document.getElementById('responseTime');
    const sslValid = document.getElementById('sslValid');
    const sslExpires = document.getElementById('sslExpires');
    const timestamp = document.getElementById('timestamp');

    // Set URL
    resultUrl.textContent = data.url;

    // Set status code with color
    statusCode.textContent = data.status_code;
    statusCode.className = 'result-value ' + getStatusClass(data.status_code);

    // Set response time with color
    responseTime.textContent = `${data.response_time_ms} ms`;
    responseTime.className = 'result-value ' + getResponseTimeClass(data.response_time_ms);

    // Set SSL valid
    if (data.ssl_valid === null) {
        sslValid.textContent = 'N/A (HTTP)';
        sslValid.className = 'result-value warning';
    } else if (data.ssl_valid) {
        sslValid.textContent = '\u2713 Valid';
        sslValid.className = 'result-value success';
    } else {
        sslValid.textContent = '\u2717 Invalid';
        sslValid.className = 'result-value error';
    }

    // Set SSL expires
    if (data.ssl_expires === null) {
        sslExpires.textContent = 'N/A';
        sslExpires.className = 'result-value';
    } else if (data.ssl_expires < 0) {
        sslExpires.textContent = 'Expired';
        sslExpires.className = 'result-value error';
    } else if (data.ssl_expires < 30) {
        sslExpires.textContent = `${data.ssl_expires} days`;
        sslExpires.className = 'result-value warning';
    } else {
        sslExpires.textContent = `${data.ssl_expires} days`;
        sslExpires.className = 'result-value success';
    }

    // Set timestamp
    const date = new Date(data.timestamp);
    timestamp.textContent = `Checked at: ${date.toLocaleString()}`;

    // Set card class
    resultCard.className = 'result-card ' + getStatusClass(data.status_code);

    // Show results
    results.classList.add('show');
}

function getStatusClass(statusCode) {
    if (statusCode >= 200 && statusCode < 300) return 'success';
    if (statusCode >= 300 && statusCode < 400) return 'warning';
    if (statusCode >= 400 && statusCode < 500) return 'warning';
    return 'error';
}

function getResponseTimeClass(responseTime) {
    if (responseTime < 300) return 'success';
    if (responseTime < 1000) return 'warning';
    return 'error';
}

function showError(message) {
    errorMessage.textContent = message;
    errorMessage.classList.add('show');
}
