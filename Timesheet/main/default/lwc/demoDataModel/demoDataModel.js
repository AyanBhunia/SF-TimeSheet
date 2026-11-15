import { LightningElement } from 'lwc';

// Diagram coordinates are viewBox units; the SVG scales to the available width.
const CARD_WIDTH = 210;
const CARD_HEIGHT = 160;
const HEADER_HEIGHT = 46;
const FIELD_ROW_HEIGHT = 19;
const ARROW_LENGTH = 9;
const ARROW_HALF_WIDTH = 5;

/** Objects in the diagram, with the fields the demo data fills in. */
const OBJECTS = [
    {
        key: 'user',
        label: 'User',
        purpose: 'You: manager, approver',
        x: 0,
        y: 185,
        width: 150,
        height: 70,
        fields: []
    },
    {
        key: 'employee',
        label: 'Employee',
        purpose: 'A person who logs time',
        x: 230,
        y: 20,
        fields: [
            { label: 'User', hint: 'You (demo employee)' },
            { label: 'Manager', hint: 'You (child employees)' },
            { label: 'Accrual Start Date' },
            { label: 'Accrual Divisor' },
            { label: 'Extra Accrued Hours' }
        ]
    },
    {
        key: 'projectEmployee',
        label: 'Project Employee',
        purpose: 'Puts an employee on a project',
        x: 570,
        y: 20,
        fields: [
            { label: 'Employee', hint: 'Master-Detail' },
            { label: 'Project', hint: 'Master-Detail' },
            { label: 'Hourly Rate' }
        ]
    },
    {
        key: 'project',
        label: 'Project',
        purpose: 'Work that hours are logged on',
        x: 910,
        y: 20,
        fields: [
            { label: 'Billable', hint: 'Yes / No' },
            { label: 'Active', hint: 'Yes / No' },
            { label: 'Start / End Date' }
        ]
    },
    {
        key: 'timesheet',
        label: 'Timesheet',
        purpose: "One employee's week",
        x: 230,
        y: 260,
        fields: [
            { label: 'Employee', hint: 'Lookup' },
            { label: 'Manager', hint: 'You approve' },
            { label: 'Start / End Date' },
            { label: 'Status', hint: 'New / Submitted / Approved' }
        ]
    },
    {
        key: 'lineItem',
        label: 'Timesheet Line Item',
        purpose: 'Hours on one day',
        x: 570,
        y: 260,
        fields: [
            { label: 'Timesheet', hint: 'Master-Detail' },
            { label: 'Date' },
            { label: 'Project / Absence', hint: 'Lookup' },
            { label: 'Activity' },
            { label: 'Duration', hint: 'Hours' }
        ]
    }
];

/**
 * Relationships, drawn from the first point to the last with an arrowhead at the end (axis-aligned
 * segments only). master: Master-Detail (solid), else Lookup (dashed).
 */
const EDGES = [
    { key: 'user-employee', points: [[75, 185], [75, 100], [230, 100]] },
    { key: 'user-timesheet', points: [[75, 255], [75, 340], [230, 340]] },
    { key: 'employee-projectEmployee', master: true, points: [[440, 100], [570, 100]] },
    { key: 'projectEmployee-project', master: true, points: [[780, 100], [910, 100]] },
    { key: 'employee-timesheet', points: [[335, 180], [335, 260]] },
    { key: 'timesheet-lineItem', master: true, points: [[440, 340], [570, 340]] },
    { key: 'lineItem-project', points: [[780, 340], [1015, 340], [1015, 180]] }
];

/** Line through the points, stopped at the arrowhead's base, plus the arrowhead triangle. */
function toEdgeShape(points) {
    const [fromX, fromY] = points[points.length - 2];
    const [tipX, tipY] = points[points.length - 1];
    const dirX = Math.sign(tipX - fromX);
    const dirY = Math.sign(tipY - fromY);
    const baseX = tipX - dirX * ARROW_LENGTH;
    const baseY = tipY - dirY * ARROW_LENGTH;
    const line = [...points.slice(0, -1), [baseX, baseY]];
    return {
        d: line.map(([x, y], index) => `${index ? 'L' : 'M'}${x},${y}`).join(' '),
        arrow: [
            [tipX, tipY],
            [baseX - dirY * ARROW_HALF_WIDTH, baseY + dirX * ARROW_HALF_WIDTH],
            [baseX + dirY * ARROW_HALF_WIDTH, baseY - dirX * ARROW_HALF_WIDTH]
        ].map(([x, y]) => `${x},${y}`).join(' ')
    };
}

/** Static data model diagram for the first step of the demo data popup: the Timesheet objects and how they relate. */
export default class DemoDataModel extends LightningElement {
    cards = OBJECTS.map((obj) => {
        const width = obj.width || CARD_WIDTH;
        return {
            key: obj.key,
            label: obj.label,
            purpose: obj.purpose,
            width,
            height: obj.height || CARD_HEIGHT,
            hintX: width - 12,
            transform: `translate(${obj.x} ${obj.y})`,
            hasFields: obj.fields.length > 0,
            dividerY: HEADER_HEIGHT,
            fields: obj.fields.map((field, index) => ({
                key: `${obj.key}-${index}`,
                label: field.label,
                hint: field.hint || '',
                y: HEADER_HEIGHT + 20 + index * FIELD_ROW_HEIGHT
            }))
        };
    });

    edges = EDGES.map((edge) => ({
        key: edge.key,
        arrowKey: `${edge.key}-arrow`,
        ...toEdgeShape(edge.points),
        className: edge.master ? 'edge edge_master' : 'edge edge_lookup'
    }));

    get diagramLabel() {
        return 'Demo data model. Your user is linked to the demo employee and manages the child employees. Project Employee assigns an employee to a project. '
            + 'An Employee logs Timesheets, which you approve. A Timesheet contains Timesheet Line Items, each logged on a Project.';
    }
}
