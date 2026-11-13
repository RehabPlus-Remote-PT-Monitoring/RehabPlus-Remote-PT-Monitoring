/*
 * New staff account: picking a role changes the example text shown in the
 * name and email fields (admin@rehabplus.com for Administrator). The example
 * is only a placeholder, so nothing is filled in unless the admin types it.
 *
 *   <select data-role-defaults>
 *     <option value="admin" data-name="Administrator" data-email="admin@rehabplus.com">
 */

/** Sets the form's name and email placeholders to the selected role's examples. */
export function applyRoleDefaults(select) {
    const option = select.selectedOptions[0];

    for (const field of ['name', 'email']) {
        select.form.querySelector(`[name="${field}"]`).placeholder = option.dataset[field];
    }
}
