// jsdom has <dialog> but not showModal()/close(); a minimal stand-in that
// behaves like the browser for what confirm.js uses.
export function installDialogPolyfill() {
    const proto = HTMLDialogElement.prototype;
    proto.showModal = function showModal() {
        this.open = true;
    };
    proto.close = function close(value) {
        if (value !== undefined) {
            this.returnValue = value;
        }
        this.open = false;
        this.dispatchEvent(new Event('close'));
    };
}

/** The open pop-up, or null. */
export const openDialog = () => document.querySelector('dialog.confirm-dialog');

/** Clicks Proceed / Cancel the way <form method="dialog"> would. */
export function answer(choice) {
    openDialog().close(choice);
}
