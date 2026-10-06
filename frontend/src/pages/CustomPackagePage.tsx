import React from 'react';
import { CustomPackageWizard } from '../components/custom-package/CustomPackageWizard';

type Props = {
  userId: string;
  apartmentId: string;
};

export function CustomPackagePage({ userId, apartmentId }: Props) {
  return <CustomPackageWizard userId={userId} apartmentId={apartmentId} />;
}
