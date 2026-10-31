// Show/hide the password. Wired up here because the Content-Security-Policy
// blocks inline onclick/onkeydown handlers.
const togglePassword = function () {
    const input = document.getElementById('passwordInput');
    const icon = document.getElementById('eyeIcon');

    if (!input || !icon) {
        return;
    }

    if (input.type === 'password') {
        input.type = 'text';
        icon.classList.replace('bi-eye', 'bi-eye-slash');
    } else {
        input.type = 'password';
        icon.classList.replace('bi-eye-slash', 'bi-eye');
    }
};

// Forgot password: count the resend cooldown down, then enable the button.
const resendButton = document.getElementById('resendButton');

if (resendButton) {
    let secondsLeft = Number(resendButton.dataset.resendIn) || 0;

    const tick = () => {
        if (secondsLeft <= 0) {
            resendButton.disabled = false;
            resendButton.textContent = 'Resend code';

            return;
        }

        resendButton.disabled = true;
        resendButton.textContent = `Resend in ${secondsLeft}s`;
        secondsLeft -= 1;
        setTimeout(tick, 1000);
    };

    tick();
}

const passwordToggle = document.getElementById('passwordToggle');

if (passwordToggle) {
    passwordToggle.addEventListener('click', togglePassword);
    passwordToggle.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            togglePassword();
        }
    });
}
