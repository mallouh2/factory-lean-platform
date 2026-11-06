const sidebarIconPaths: Record<string, string[]> = {
  manageLinesMachines:['M2 9h5v6H2z','M10 9h5v6h-5z','M18 9h4v6h-4z','M7 12h3','M15 12h3'],
  notifications:['M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9','M10 21h4'],
  quality:['M12 3 3 7v6c0 5 9 9 9 9s9-4 9-9V7z','M8 12l3 3 5-6'],
  lean:['M3 3v18h18','M7 15l4-5 4 3 5-7'],
  purchasing: ['M5 7h14l2 14H3z','M8 7V5a4 4 0 0 1 8 0v2'],
  myPurchaseRequests: ['M5 3h14v18H5z','M8 7h8','M8 11h8','M8 16l2 2 5-5'],
  materialRequests: ['M3 7l9-4 9 4-9 4z','M3 7v10l9 4 9-4V7','M12 11v10'],
  suppliers: ['M3 21V7l9-4 9 4v14','M7 9h2','M15 9h2','M9 21v-6h6v6'],
  platform: ["M3 21h18", "M5 21V7l7-4 7 4v14", "M9 10h.01", "M15 10h.01", "M9 14h.01", "M15 14h.01", "M10 21v-4h4v4"],
  dashboard: ["M3 3h8v8H3z", "M13 3h8v8h-8z", "M3 13h8v8H3z", "M13 13h8v8h-8z"],
  floor: ['M3 21V10l6-4v6l6-4v5h6v8z','M17 13V3h3v10','M7 17h2','M12 17h2'],
  production: ['M3 21V10l6-4v6l6-4v5h6v8z','M17 13V3h3v10'],
  productionHistory: ['M3 11a9 9 0 1 1 2 7','M3 4v7h7','M12 7v5l3 2'],
  warehouseRequests: ['M4 5h16v14H4z','M4 9h16','M8 13l-2 2 2 2','M13 15h5'],
  lines: ["M2 9h5v6H2z", "M10 9h5v6h-5z", "M18 9h4v6h-4z", "M7 12h3", "M15 12h3"],
  sales: ["M5 3h14v18H5z", "M8 7h8", "M8 11h8", "M8 15h5"],
  warehouse: ["M3 10 12 3l9 7v11H3z", "M8 21v-8h8v8", "M8 17h8"],
  orders: ["M8 4h8", "M9 3h6v3H9z", "M7 5H5v16h14V5h-2", "M8 11h8", "M8 15h8", "M8 19h5"],
  planning: ["M3 5h18v16H3z", "M3 10h18", "M8 3v4", "M16 3v4", "M7 15h4", "M14 15h3"],
  products: ["M3 7 12 3l9 4v10l-9 4-9-4z", "M3 7l9 4 9-4", "M12 11v10"],
  downtime: ["M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z", "M10 9v6", "M14 9v6"],
  maintenance: ['M14 6a5 5 0 0 0-6 6L3 17a3 3 0 0 0 4 4l5-5a5 5 0 0 0 6-6l-3 3-4-4z'],
  reports: ["M4 20V10h4v10", "M10 20V5h4v15", "M16 20v-8h4v8", "M3 20h18"],
  employees: ["M9 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z", "M2 20v-2a7 7 0 0 1 14 0v2", "M17 5a4 4 0 0 1 0 7", "M19 14a6 6 0 0 1 3 5v1"],
  roles: ["M5 4h14v16H5z", "M9 9a2 2 0 1 0 4 0 2 2 0 0 0-4 0z", "M8 16a3 3 0 0 1 6 0", "M16 9h1", "M16 13h1"],
  settings: ["M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z", "M10 2h4l.5 2.3 1.5.7 2-.9 2.8 2.8-.9 2 .7 1.5L23 11v2l-2.4.5-.7 1.5.9 2-2.8 2.8-2-.9-1.5.7L14 22h-4l-.5-2.4-1.5-.7-2 .9-2.8-2.8.9-2-.7-1.5L1 13v-2l2.4-.6.7-1.5-.9-2L6 4.1l2 .9 1.5-.7z"],
  support: ["M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z", "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z", "M5.6 5.6 9.2 9.2", "M14.8 14.8l3.6 3.6", "M18.4 5.6l-3.6 3.6", "M9.2 14.8l-3.6 3.6"],
  audit: ["M6 3h9l4 4v14H6z", "M15 3v4h4", "M9 12h7", "M9 16h4", "M16 16l1.5 1.5L20 15"],
  preview: ["M2 12s3.6-6 10-6 10 6 10 6-3.6 6-10 6S2 12 2 12z", "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z"],
};
export default function SidebarIcon({ name }: { name: string }) {
  return <svg className="sidebar-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {(sidebarIconPaths[name] || sidebarIconPaths.dashboard).map((path, index) => <path key={index} d={path} />)}
  </svg>;
}
