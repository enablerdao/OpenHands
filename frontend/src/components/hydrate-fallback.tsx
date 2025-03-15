import React from "react";

export function HydrateFallback() {
  return (
    <div className="flex items-center justify-center min-h-screen bg-gray-100">
      <div className="text-center p-8 max-w-md">
        <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500 mx-auto mb-4"></div>
        <h2 className="text-xl font-semibold mb-2">Loading OpenHands...</h2>
        <p className="text-gray-600">
          We're preparing your development environment. This may take a moment.
        </p>
      </div>
    </div>
  );
}
