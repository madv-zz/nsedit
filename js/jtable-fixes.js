/*
 * Fixes for jTable 2.6.0 (unmaintained since 2018) with jQuery 3.7 and jQuery UI 1.14.
 *
 * Deleting a row: jTable waits until its "deleting" class animation is finished before it removes the row
 * (.addClass(class, 'slow').promise().done(...)). With jQuery UI 1.14 that promise does not resolve while
 * the row still runs the 5 second highlight of a recent create or update. A record that was created or
 * changed less than 5 seconds ago was then deleted on the server, but stayed in the table.
 * This version stops the highlight and removes the row directly.
 */
(function ($) {
    'use strict';

    $.hik.jtable.prototype._removeRowsFromTableWithAnimation = function ($rows) {
        $rows.stop(true, true).removeClass('jtable-row-created jtable-row-updated');
        this._removeRowsFromTable($rows, 'deleted');
    };
})(jQuery);
