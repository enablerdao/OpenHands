import { redirect, useSearchParams } from "react-router";
import React from "react";
import { PaymentForm } from "#/components/features/payment/payment-form";
import { GetConfigResponse } from "#/api/open-hands.types";
import { queryClient } from "#/entry.client";
import {
  displayErrorToast,
  displaySuccessToast,
} from "#/utils/custom-toast-handlers";
import { BILLING_SETTINGS } from "#/utils/feature-flags";

export const clientLoader = async () => {
  const config = queryClient.getQueryData<GetConfigResponse>(["config"]);

  if (config?.APP_MODE !== "saas" || !BILLING_SETTINGS()) {
    return redirect("/settings");
  }

  return null;
};

// Add hydrate property to clientLoader
clientLoader.hydrate = true;

// Add HydrateFallback component for route-specific loading state
export function HydrateFallback() {
  return (
    <div className="flex items-center justify-center min-h-screen bg-gray-100">
      <div className="text-center p-8 max-w-md">
        <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500 mx-auto mb-4"></div>
        <h2 className="text-xl font-semibold mb-2">Loading billing settings...</h2>
      </div>
    </div>
  );
}

function BillingSettingsScreen() {
  const [searchParams, setSearchParams] = useSearchParams();
  const checkoutStatus = searchParams.get("checkout");

  React.useEffect(() => {
    if (checkoutStatus === "success") {
      displaySuccessToast("Payment successful");
    } else if (checkoutStatus === "cancel") {
      displayErrorToast("Payment cancelled");
    }

    setSearchParams({});
  }, [checkoutStatus]);

  return <PaymentForm />;
}

export default BillingSettingsScreen;
