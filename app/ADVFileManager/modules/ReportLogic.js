document.addEventListener("DOMContentLoaded", function() {
    // Initial setup: collapse all folders in the main tree.
    toggleAll('report-body', false);
});

/**
 * Toggles the visibility of child rows for a given parent folder row.
 * @param {HTMLElement} row The folder row (<tr>) that was clicked.
 */
function toggleChildren(row) {
    const rowId = row.id;
    if (!rowId || !row.classList.contains('folder-row')) return;

    const caret = row.querySelector(".caret");
    const isExpanded = caret.classList.contains("caret-down");
    const children = document.querySelectorAll(`#report-body .child-of-${rowId}`);

    caret.classList.toggle("caret-down", !isExpanded);

    children.forEach(child => {
        // Toggle visibility of direct children
        child.classList.toggle("hidden", isExpanded);

        // If we are collapsing, ensure all descendants of this child are also hidden.
        if (isExpanded && child.classList.contains('folder-row')) {
            const subCaret = child.querySelector(".caret");
            if (subCaret && subCaret.classList.contains('caret-down')) {
                toggleChildren(child); // Recursively collapse
            }
        }
    });
}


/**
 * Expands or collapses all folder rows in the main tree view.
 * @param {string} tableBodyId The ID of the tbody element.
 * @param {boolean} expand True to expand all, false to collapse all.
 */
function toggleAll(tableBodyId, expand) {
    if (tableBodyId !== 'report-body') return; // This function is for the main tree only

    const rows = document.querySelectorAll(`#${tableBodyId} tr`);
    rows.forEach(row => {
        // Show or hide based on expand flag, but keep root items visible.
        const isRoot = !row.className.includes('child-of-');
        row.classList.toggle('hidden', !expand && !isRoot);

        if (row.classList.contains('folder-row')) {
            const caret = row.querySelector('.caret');
            if (caret) {
                caret.classList.toggle('caret-down', expand);
            }
        }
    });
}

/**
 * Searches a table and shows only matching rows and their parent folders.
 * @param {string} inputId The ID of the search input box.
 * @param {string} tableBodyId The ID of the tbody element to search within.
 */
function searchTable(inputId, tableBodyId) {
    const filter = document.getElementById(inputId).value.toLowerCase();
    const rows = document.querySelectorAll(`#${tableBodyId} tr`);
    const isTreeView = tableBodyId === 'report-body';

    // If search is cleared, reset the view
    if (filter === "") {
        rows.forEach(row => {
            row.style.display = ""; // Remove inline style to revert to CSS 'display'
        });
        if (isTreeView) {
            toggleAll(tableBodyId, false); // Collapse tree view on clear
        }
        return;
    }
    
    // In tree view, we need to manage hierarchy visibility
    if (isTreeView) {
        const matchingRows = new Set();
        rows.forEach(row => {
            const textContent = row.textContent || row.innerText;
            if (textContent.toLowerCase().includes(filter)) {
                // Add the matching row and all its ancestors to the set
                let current = row;
                while (current) {
                    matchingRows.add(current);
                    const parentClass = Array.from(current.classList).find(c => c.startsWith('child-of-'));
                    if (parentClass) {
                        const parentId = parentClass.substring('child-of-'.length);
                        current = document.getElementById(parentId);
                    } else {
                        current = null;
                    }
                }
            }
        });

        rows.forEach(row => {
            if (matchingRows.has(row)) {
                row.style.display = "";
                // Ensure caret is expanded for visible folders
                if (row.classList.contains('folder-row')) {
                    const caret = row.querySelector('.caret');
                    if (caret) caret.classList.add('caret-down');
                }
            } else {
                row.style.display = "none";
            }
        });
    } else { // For flat tables (e.g., recent files)
        rows.forEach(row => {
            const textContent = row.textContent || row.innerText;
            row.style.display = textContent.toLowerCase().includes(filter) ? "" : "none";
        });
    }
}

/**
 * Sorts a table by a specific column.
 * @param {HTMLElement} th The table header (<th>) element that was clicked.
 * @param {number} colIndex The index of the column to sort by.
 * @param {string} type The data type for sorting ('string', 'size', 'date').
 */
function sortTable(th, colIndex, type = 'string') {
    const table = th.closest('table');
    const tbody = table.querySelector('tbody');
    const isTreeView = tbody.id === 'report-body';
    
    const sortDirection = th.classList.contains('sorted-asc') ? 'desc' : 'asc';
    
    // Reset other headers in the same table
    table.querySelectorAll('th.sortable').forEach(header => {
        header.classList.remove('sorted-asc', 'sorted-desc', 'sorted');
    });
    
    th.classList.add('sorted', sortDirection === 'asc' ? 'sorted-asc' : 'sorted-desc');

    const parseSize = (text) => {
        if (!text) return 0;
        const parts = text.trim().match(/([\d.,]+)\s*(\wB)?/);
        if (!parts) return 0;
        let value = parseFloat(parts[1].replace(',', '.'));
        const unit = (parts[2] || 'B').toUpperCase();
        switch (unit) {
            case 'GB': value *= 1024 * 1024 * 1024; break;
            case 'MB': value *= 1024 * 1024; break;
            case 'KB': value *= 1024; break;
        }
        return value;
    };
    
    const parseDate = (text) => {
        if (!text) return 0;
        const parts = text.match(/(\d{2})-(\d{2})-(\d{4})\s*(\d{2}):(\d{2})/); // dd-MM-yyyy HH:mm
        if (!parts) return new Date(0);
        return new Date(parts[3], parts[2] - 1, parts[1], parts[4], parts[5]).getTime();
    };

    const getValue = (row, type) => {
        const cell = row.cells[colIndex];
        const text = cell ? (cell.textContent || cell.innerText) : '';
        switch (type) {
            case 'size': return parseSize(text);
            case 'date': return parseDate(text);
            case 'string':
            default: return text.trim().toLowerCase();
        }
    };
    
    // Sort logic depends on whether it's a tree or a flat table
    if (isTreeView) {
        // For the tree, we sort children within each parent node
        const parents = Array.from(tbody.querySelectorAll('.folder-row, .file-row:not([class*="child-of-"])'));
        const rootNodes = parents.filter(p => !p.className.includes('child-of-'));
        
        const sortNodes = (nodes) => {
             nodes.sort((a, b) => {
                const valA = getValue(a, type);
                const valB = getValue(b, type);
                const result = valA < valB ? -1 : (valA > valB ? 1 : 0);
                return sortDirection === 'asc' ? result : -result;
             });
             return nodes;
        };

        const processChildren = (parentId) => {
            const children = Array.from(tbody.querySelectorAll(`tr.child-of-${parentId}`));
            const sortedChildren = sortNodes(children);
            
            // Re-append sorted children and recurse
            sortedChildren.forEach(child => {
                tbody.appendChild(child);
                if (child.classList.contains('folder-row')) {
                    processChildren(child.id);
                }
            });
        };
        
        // Sort root nodes first
        sortNodes(rootNodes).forEach(rootNode => {
            tbody.appendChild(rootNode);
            if (rootNode.classList.contains('folder-row')) {
                processChildren(rootNode.id);
            }
        });

    } else { // For flat tables
        const rows = Array.from(tbody.querySelectorAll('tr'));
        rows.sort((a, b) => {
            const valA = getValue(a, type);
            const valB = getValue(b, type);
            const result = valA < valB ? -1 : (valA > valB ? 1 : 0);
            return sortDirection === 'asc' ? result : -result;
        });
        rows.forEach(row => tbody.appendChild(row));
    }
}