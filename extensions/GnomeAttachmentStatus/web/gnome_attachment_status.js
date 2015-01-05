function showOrHideGnomeAttachmentStatus() {
    var combo = document.getElementById('gnome_attachment_status_combo');
    var hidden = document.getElementById('gnome_attachment_status_hidden');
    var ispatch = document.getElementById('ispatch');

    if (combo === null || hidden === null || ispatch === null) {
	return 1;
    }

    combo.disabled = !ispatch.checked
    hidden.disabled = ispatch.checked

    return 1;
}

document.addEventListener('DOMContentLoaded', function () {
    ispatch = document.getElementById('ispatch');
    if (ispatch !== null) {
	ispatch.addEventListener('change', showOrHideGnomeAttachmentStatus);
    }
});
