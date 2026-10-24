CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$ BEGIN
  CREATE TYPE cleaner_skill_level AS ENUM ('JUNIOR', 'MIDDLE', 'SENIOR', 'EXPERT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE order_status AS ENUM ('PENDING', 'ASSIGNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS cleaners (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  daily_work_limit_hours NUMERIC(6,2) NOT NULL DEFAULT 8,
  monthly_assigned_area NUMERIC(10,2) NOT NULL DEFAULT 0,
  monthly_assigned_hours NUMERIC(10,2) NOT NULL DEFAULT 0,
  monthly_assigned_apartments INTEGER NOT NULL DEFAULT 0,
  skill_level cleaner_skill_level NOT NULL DEFAULT 'MIDDLE',
  preferred_zones TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS apartments (
  id UUID PRIMARY KEY,
  address TEXT NOT NULL,
  district TEXT NOT NULL,
  area NUMERIC(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY,
  apartment_id UUID NOT NULL REFERENCES apartments(id),
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  area NUMERIC(10,2) NOT NULL,
  estimated_duration_hours NUMERIC(6,2) NOT NULL,
  district TEXT NOT NULL,
  status order_status NOT NULL DEFAULT 'PENDING',
  cleaner_id UUID NULL REFERENCES cleaners(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS assignments (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders(id) UNIQUE,
  cleaner_id UUID NOT NULL REFERENCES cleaners(id),
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fairness_score_snapshot JSONB NOT NULL,
  manual_override BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_date_status ON orders(date, status);
CREATE INDEX IF NOT EXISTS idx_orders_cleaner ON orders(cleaner_id, date);
CREATE INDEX IF NOT EXISTS idx_assignments_cleaner ON assignments(cleaner_id, assigned_at);
CREATE INDEX IF NOT EXISTS idx_apartments_district ON apartments(district);

CREATE TABLE IF NOT EXISTS package_plans (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  cleaning_count INTEGER NOT NULL,
  valid_from DATE NOT NULL,
  valid_to DATE NOT NULL,
  allow_same_day BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_packages (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  package_id UUID NOT NULL REFERENCES package_plans(id),
  apartment_id UUID NOT NULL REFERENCES apartments(id),
  total_cleanings INTEGER NOT NULL,
  booked_cleanings INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cleaning_slots (
  id UUID PRIMARY KEY,
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  available_capacity INTEGER NOT NULL,
  district TEXT NOT NULL,
  is_closed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS scheduled_cleanings (
  id UUID PRIMARY KEY,
  user_package_id UUID NOT NULL REFERENCES user_packages(id),
  apartment_id UUID NOT NULL REFERENCES apartments(id),
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  status TEXT NOT NULL DEFAULT 'BOOKED',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS closed_days (
  day DATE PRIMARY KEY,
  reason TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cleaning_slots_date ON cleaning_slots(date, district);
CREATE INDEX IF NOT EXISTS idx_scheduled_cleanings_package ON scheduled_cleanings(user_package_id, date);
CREATE INDEX IF NOT EXISTS idx_user_packages_user ON user_packages(user_id, status);

DO $$ BEGIN
  CREATE TYPE addon_pricing_type AS ENUM ('FIXED', 'PER_VISIT', 'PER_SQM');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS addons (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  pricing_type addon_pricing_type NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  repeatable BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS custom_package_drafts (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  apartment_id UUID NOT NULL REFERENCES apartments(id),
  area NUMERIC(10,2) NOT NULL,
  cleaning_count INTEGER NOT NULL,
  base_cleaning_type TEXT NOT NULL,
  recurring_addons UUID[] NOT NULL DEFAULT '{}',
  one_time_addons UUID[] NOT NULL DEFAULT '{}',
  preferred_days TEXT[] NOT NULL DEFAULT '{}',
  preferred_time_ranges TEXT[] NOT NULL DEFAULT '{}',
  estimated_monthly_price NUMERIC(10,2) NOT NULL DEFAULT 0,
  config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS custom_packages (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  apartment_id UUID NOT NULL REFERENCES apartments(id),
  config_json JSONB NOT NULL,
  monthly_price NUMERIC(10,2) NOT NULL,
  discount NUMERIC(10,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'DRAFT',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_custom_package_drafts_user ON custom_package_drafts(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_custom_packages_user ON custom_packages(user_id, status);

DO $$ BEGIN
  CREATE TYPE cleaner_status AS ENUM ('NEWBIE', 'SPECIALIST', 'PROFESSIONAL', 'SUPERWOMAN', 'EXPERT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE cleaners
  ADD COLUMN IF NOT EXISTS status cleaner_status NOT NULL DEFAULT 'NEWBIE',
  ADD COLUMN IF NOT EXISTS current_rating NUMERIC(3,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS average_rating_30d NUMERIC(3,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS average_rating_90d NUMERIC(3,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS work_start_date DATE,
  ADD COLUMN IF NOT EXISTS completed_orders_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS complaints_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cancellation_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS late_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS auto_promotion_locked BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS district TEXT;

ALTER TABLE assignments
  ADD COLUMN IF NOT EXISTS assignment_priority_type TEXT,
  ADD COLUMN IF NOT EXISTS addon_priority_score NUMERIC(10,4),
  ADD COLUMN IF NOT EXISTS fairness_score NUMERIC(10,4),
  ADD COLUMN IF NOT EXISTS reason_snapshot JSONB;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS base_price NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS addon_total_price NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_price NUMERIC(10,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS cleaner_status_history (
  id UUID PRIMARY KEY,
  cleaner_id UUID NOT NULL REFERENCES cleaners(id),
  old_status cleaner_status,
  new_status cleaner_status NOT NULL,
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cleaner_monthly_stats (
  cleaner_id UUID NOT NULL REFERENCES cleaners(id),
  month TEXT NOT NULL,
  total_area NUMERIC(10,2) NOT NULL DEFAULT 0,
  total_hours NUMERIC(10,2) NOT NULL DEFAULT 0,
  total_orders INTEGER NOT NULL DEFAULT 0,
  total_income NUMERIC(10,2) NOT NULL DEFAULT 0,
  addon_income NUMERIC(10,2) NOT NULL DEFAULT 0,
  high_addon_orders_count INTEGER NOT NULL DEFAULT 0,
  medium_addon_orders_count INTEGER NOT NULL DEFAULT 0,
  low_addon_orders_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (cleaner_id, month)
);

CREATE TABLE IF NOT EXISTS status_config (
  status cleaner_status PRIMARY KEY,
  min_rating NUMERIC(3,2) NOT NULL,
  min_rating_period_days INTEGER NOT NULL,
  min_completed_orders INTEGER NOT NULL,
  max_complaints_rate NUMERIC(6,4) NOT NULL,
  max_cancellation_rate NUMERIC(6,4) NOT NULL,
  max_late_rate NUMERIC(6,4) NOT NULL,
  min_tenure_days INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS assignment_config (
  id TEXT PRIMARY KEY,
  high_addon_threshold NUMERIC(10,2) NOT NULL,
  medium_addon_threshold NUMERIC(10,2) NOT NULL,
  weight_status_priority NUMERIC(6,4) NOT NULL,
  weight_fairness NUMERIC(6,4) NOT NULL,
  weight_monthly_addon_balance NUMERIC(6,4) NOT NULL,
  weight_hours_balance NUMERIC(6,4) NOT NULL,
  weight_area_balance NUMERIC(6,4) NOT NULL,
  weight_distance NUMERIC(6,4) NOT NULL,
  randomness_factor NUMERIC(6,4) NOT NULL
);

INSERT INTO status_config (status, min_rating, min_rating_period_days, min_completed_orders, max_complaints_rate, max_cancellation_rate, max_late_rate, min_tenure_days)
VALUES
  ('NEWBIE', 0, 0, 0, 1, 1, 1, 0),
  ('SPECIALIST', 4.5, 0, 10, 0.10, 0.10, 0.10, 14),
  ('PROFESSIONAL', 4.9, 30, 30, 0.05, 0.05, 0.05, 30),
  ('SUPERWOMAN', 4.9, 90, 80, 0.03, 0.03, 0.03, 90),
  ('EXPERT', 4.9, 90, 200, 0.01, 0.02, 0.02, 365)
ON CONFLICT (status) DO NOTHING;

INSERT INTO assignment_config (id, high_addon_threshold, medium_addon_threshold, weight_status_priority, weight_fairness, weight_monthly_addon_balance, weight_hours_balance, weight_area_balance, weight_distance, randomness_factor)
VALUES ('default', 10000, 5000, 0.34, 0.24, 0.16, 0.10, 0.08, 0.04, 0.04)
ON CONFLICT (id) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_cleaner_status_history_cleaner ON cleaner_status_history(cleaner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cleaner_monthly_stats_month ON cleaner_monthly_stats(month);

DO $$ BEGIN
  CREATE TYPE app_role AS ENUM ('customer', 'cleaner', 'admin', 'superadmin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE profile_status AS ENUM ('new', 'pending', 'approved', 'rejected', 'blocked');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE payment_status AS ENUM ('draft', 'invoice_requested', 'pending', 'paid', 'rejected', 'refunded', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE payment_provider AS ENUM ('kaspi', 'bcc', 'bonus', 'manual');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE bonus_type AS ENUM ('accrual', 'spend', 'refund', 'correction');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE complaint_status AS ENUM ('open', 'in_progress', 'closed', 'compensation', 'refund');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE quality_status AS ENUM ('pending', 'scheduled', 'approved', 'rejected', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE preorder_status AS ENUM ('new', 'notified', 'paid', 'worked', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS app_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  numeric_id BIGSERIAL UNIQUE,
  firebase_uid TEXT UNIQUE,
  role app_role NOT NULL,
  phone TEXT UNIQUE NOT NULL,
  password_hash TEXT,
  full_name TEXT,
  email TEXT,
  language TEXT NOT NULL DEFAULT 'ru',
  rating NUMERIC(3,2) NOT NULL DEFAULT 5,
  bonus_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
  status profile_status NOT NULL DEFAULT 'new',
  is_phone_verified BOOLEAN NOT NULL DEFAULT FALSE,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- A phone identifies a person; customer and cleaner profiles remain separate.
ALTER TABLE app_users DROP CONSTRAINT IF EXISTS app_users_phone_key;
CREATE UNIQUE INDEX IF NOT EXISTS app_users_phone_role_key ON app_users(phone,role);

CREATE TABLE IF NOT EXISTS auth_otp_codes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT 'wapi',
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE auth_otp_codes ADD COLUMN IF NOT EXISTS role app_role;
CREATE INDEX IF NOT EXISTS auth_otp_phone_role ON auth_otp_codes(phone,role,created_at DESC);

CREATE TABLE IF NOT EXISTS refresh_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  device_id TEXT,
  user_agent TEXT,
  ip TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customer_addresses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  city TEXT NOT NULL,
  settlement TEXT,
  street TEXT NOT NULL,
  house TEXT NOT NULL,
  apartment TEXT,
  entrance TEXT,
  floor TEXT,
  intercom TEXT,
  access_comment TEXT,
  area NUMERIC(10,2),
  verified_area NUMERIC(10,2),
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  is_primary BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE customer_addresses ADD COLUMN IF NOT EXISTS residential_complex TEXT;

CREATE TABLE IF NOT EXISTS cleaner_profiles (
  user_id UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
  city TEXT NOT NULL DEFAULT 'Астана',
  registration_status profile_status NOT NULL DEFAULT 'pending',
  verification_status profile_status NOT NULL DEFAULT 'pending',
  work_start_date DATE,
  monthly_area_limit NUMERIC(10,2) NOT NULL DEFAULT 220,
  daily_work_limit_minutes INTEGER NOT NULL DEFAULT 540,
  sound_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  sound_volume INTEGER NOT NULL DEFAULT 100,
  sound_key TEXT NOT NULL DEFAULT 'system',
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cleaner_documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cleaner_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  file_id UUID,
  status profile_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS service_zones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name_ru TEXT NOT NULL,
  name_kk TEXT,
  city TEXT NOT NULL,
  polygon JSONB,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cleaner_zones (
  cleaner_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  zone_id UUID NOT NULL REFERENCES service_zones(id) ON DELETE CASCADE,
  PRIMARY KEY (cleaner_id, zone_id)
);

CREATE TABLE IF NOT EXISTS connected_houses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  city TEXT NOT NULL,
  street_ru TEXT NOT NULL,
  street_kk TEXT,
  house TEXT NOT NULL,
  residential_complex_ru TEXT,
  residential_complex_kk TEXT,
  zone_id UUID REFERENCES service_zones(id),
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS service_address_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
  city TEXT,
  residential_complex TEXT,
  address TEXT NOT NULL,
  address_place_id TEXT,
  entrance TEXT,
  apartment TEXT,
  area NUMERIC(10,2),
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  status TEXT NOT NULL DEFAULT 'waiting',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_service_address_requests_status_created ON service_address_requests(status, created_at DESC);

CREATE TABLE IF NOT EXISTS catalog_packages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name_ru TEXT NOT NULL,
  name_kk TEXT,
  description_ru TEXT,
  description_kk TEXT,
  cleaning_count INTEGER NOT NULL,
  months INTEGER NOT NULL DEFAULT 1,
  base_price NUMERIC(12,2) NOT NULL,
  price_per_m2 NUMERIC(12,2) NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  features JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS addon_groups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS catalog_addons (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id UUID REFERENCES addon_groups(id),
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  description_ru TEXT,
  description_kk TEXT,
  hint_ru TEXT,
  hint_kk TEXT,
  pricing_type TEXT NOT NULL DEFAULT 'fixed',
  price NUMERIC(12,2) NOT NULL DEFAULT 0,
  duration_minutes INTEGER NOT NULL DEFAULT 0,
  paid_separately BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS checklist_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  package_id UUID REFERENCES catalog_packages(id),
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS checklist_template_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_id UUID NOT NULL REFERENCES checklist_templates(id) ON DELETE CASCADE,
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS promotions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  description_ru TEXT,
  description_kk TEXT,
  package_id UUID REFERENCES catalog_packages(id),
  reward_type TEXT NOT NULL DEFAULT 'fixed',
  reward_value NUMERIC(12,2) NOT NULL DEFAULT 0,
  max_bonus_spend_percent NUMERIC(5,2),
  once_per_customer BOOLEAN NOT NULL DEFAULT FALSE,
  banner_file_id UUID,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE promotions ADD COLUMN IF NOT EXISTS presentation JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE promotions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS banners (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  description_ru TEXT,
  description_kk TEXT,
  image_file_id UUID,
  target_type TEXT NOT NULL DEFAULT 'modal',
  target_value TEXT,
  placement TEXT NOT NULL DEFAULT 'home_top',
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE addon_groups ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE addon_groups ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE promotions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE banners ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE banners ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS subtitle_ru TEXT;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS subtitle_kk TEXT;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS cta_label_ru TEXT;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS cta_label_kk TEXT;
UPDATE banners SET placement='home_top', updated_at=NOW() WHERE placement='home_info';

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app_settings (key, value)
VALUES
  ('baseCleaningMinutes', '120'::jsonb),
  ('minutesPerM2', '1.2'::jsonb),
  ('slotStartTimes', '["08:00","10:00","12:00","14:00","16:00"]'::jsonb),
  ('qualityCheckHours', '48'::jsonb),
  ('bonusPaymentEnabled', 'true'::jsonb),
  ('defaultBonusMaxPercent', '50'::jsonb),
  ('customerTierRules', '[
    {"tier":"NEWBIE","labelRu":"Наш любимый Новичок","labelKk":"Біздің сүйікті Жаңадан бастаушы","minMonthlySpent":0,"maxMonthlySpent":100000,"discountPercent":0,"sortOrder":0},
    {"tier":"CLEANSTER","labelRu":"Наш любимый Чистюля","labelKk":"Біздің сүйікті Тазалық жанашыры","minMonthlySpent":100000,"maxMonthlySpent":500000,"discountPercent":5,"sortOrder":1},
    {"tier":"GURU","labelRu":"Гуру чистоты","labelKk":"Тазалық гуруы","minMonthlySpent":500000,"maxMonthlySpent":1500000,"discountPercent":10,"sortOrder":2},
    {"tier":"GOD","labelRu":"Бог чистоты","labelKk":"Тазалық құдайы","minMonthlySpent":1500000,"maxMonthlySpent":null,"discountPercent":10,"sortOrder":3}
  ]'::jsonb),
  ('minBookingDate', 'null'::jsonb),
  ('cleanerOfferTtlMinutes', '2'::jsonb),
  ('cleanerQuietHoursEnabled', 'false'::jsonb),
  ('cleanerQuietHoursStart', '"23:00"'::jsonb),
  ('cleanerQuietHoursEnd', '"07:00"'::jsonb),
  ('requireAvailableCleaner', 'true'::jsonb),
  ('allowCustomTime', 'false'::jsonb),
  ('scrollToPendingAfterAddonSelection', 'true'::jsonb),
  ('allowBonusForPackagePurchase', 'false'::jsonb),
  ('skipZeroAmountInvoice', 'true'::jsonb),
  ('qualityCheckRequiredAfterPackagePurchase', 'true'::jsonb),
  ('qualityCheckNotificationTitleRu', '"Назначена проверка площади"'::jsonb),
  ('qualityCheckNotificationBodyRu', '"В течение 48 часов отдел контроля качества приедет к вам для проверки площади. Также вы можете пройти проверку в приложении, загрузив план квартиры."'::jsonb),
  ('qualityCheckNotificationTitleKk', '"Ауданды тексеру тағайындалды"'::jsonb),
  ('qualityCheckNotificationBodyKk', '"48 сағат ішінде сапаны бақылау бөлімі пәтер ауданын тексеру үшін келеді. Сонымен қатар қосымшада пәтер жоспарын жүктеп, тексеруден өте аласыз."'::jsonb),
  ('featureFlags', '{"preordersEnabled":true,"qualityCheckEnabled":true,"onlinePaymentEnabled":true,"kaspiPaymentEnabled":true,"bonusPaymentEnabled":true,"cleanerManualAssignmentEnabled":true,"inAppTrainingEnabled":true}'::jsonb),
  ('customerTabs', '["home","orders","profile","notifications","settings"]'::jsonb),
  ('cleanerTabs', '["home","calendar","orders","messages","profile"]'::jsonb),
  ('paymentFlow', '{"afterInvoiceAction":"home","showPackagePurchaseButtonUntilPaid":true,"showCleaningOrderButtonOnlyWithAvailableCleanings":true,"requireBonusCheckbox":true,"hideExternalInvoiceForZeroPayable":true,"invoiceAmountUsesPayableAfterBonus":true,"createInvoiceOnlyAfterExplicitPaymentChoice":true,"showPaymentBreakdownEverywhere":true}'::jsonb),
  ('uiBehavior', '{"customerHomeOrderCardAction":"booking","addonSelectionAfterApply":"pending_orders","packageSelectionPosition":"center","bannerFit":"contain","autoRotateImportantBanners":true,"bottomNavEvenSpacing":true,"stickyAddonButtons":true,"noEllipsisForImportantLabels":true,"hideBackButtonOnBottomTabs":true}'::jsonb),
  ('validationRules', '{"areaInput":"decimal_round_up","requireAreaBeforePackage":true,"requireQualityCheckPhotoAndArea":true,"addressSearchLimit":10,"addressSearchRadiusKm":50,"blockQualitySubmitUntilComplete":true}'::jsonb),
  ('errorMessages', '{"unauthorized":{"ru":"Сессия истекла. Войдите заново.","kk":"Сессия аяқталды. Қайта кіріңіз."},"paymentRequired":{"ru":"Сначала подтвердите оплату.","kk":"Алдымен төлемді растаңыз."},"cleanerUnavailable":{"ru":"На это время нет свободной уборщицы. Выберите другое время.","kk":"Бұл уақытта бос орындаушы жоқ. Басқа уақыт таңдаңыз."}}'::jsonb),
  ('appText', '{"qualityCheck48h":{"ru":"В течение 48 часов отдел контроля качества приедет к вам для проверки площади.","kk":"48 сағат ішінде сапаны бақылау бөлімі ауданды тексеру үшін келеді."},"bonusPaymentLabel":{"ru":"Оплатить бонусами","kk":"Бонустармен төлеу"}}'::jsonb),
  ('enabledLanguages', '["ru","kk"]'::jsonb),
  ('defaultLanguage', '"ru"'::jsonb),
  ('translationMode', '{"liveSwitch":true,"adminEditable":true,"fallbackLanguage":"ru","dynamicDataLocales":true}'::jsonb),
  ('addressSearch', '{"primaryProvider":"osm","fallbackProvider":"yandex","fallbackOnlyOnEmptyOrError":true,"cityFromGeolocation":true,"radiusKm":50,"limit":10,"excludeOrganizations":true,"includeResidentialComplexes":true,"includeStreets":true,"fillDestinationAutomatically":false,"fromFieldFormat":"street_house_settlement"}'::jsonb),
  ('assignmentRules', '{"requireAvailableCleanerForSlot":true,"useCleanerLocationPriority":true,"preventTimeOverlap":true,"reassignOnCleanerConflict":true,"respectMonthlyAreaLimit":true,"respectDailyWorkMinutes":true,"allowOverAreaLimitIfTimeAvailable":true}'::jsonb),
  ('orderRules', '{"hidePreorderButtonAfterPreorderOrPackage":true,"preorderMovesToOrdersOnlyAfterStartAndPayment":true,"cancelRefundsBonuses":true,"cancelRemovesPaidAddons":true,"suppressDuplicateSearchingCleanerNotification":true,"hideCleanerEarningsFromCleanerApp":true,"showOnlyAvailableCleanerSlots":true,"routeHomeEmptyOrderCardToBooking":true,"blockCleaningOrderUntilPackagePaid":true,"keepPreordersOutOfOrdersUntilPaid":true}'::jsonb),
  ('adminNotificationRules', '{"enabled":true,"events":["new_user","new_cleaner","new_order","new_payment","quality_check","preorder","complaint","review","payout"],"deepLinks":true,"routeByTargetType":true}'::jsonb),
  ('contentRules', '{"privacyPolicyEditable":true,"offerEditable":true,"bannerDetailsModal":true,"importantBannersAutoRotate":true,"hideRawImageUrlInModals":true}'::jsonb),
  ('trainingFlow', '{"enabled":true,"backendStepsEditable":true,"interactiveMode":true,"testOrderMode":true,"resetKey":"training_v2"}'::jsonb),
  ('screenRules', '{"ordersTabs":["orders","package_purchases","cleaning_visits"],"adminSortDefault":"newest_first","adminDateFiltersEnabled":true,"adminShowNumericIdsOnly":true,"userIdsMode":"sequential_numeric"}'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS translations (
  key TEXT PRIMARY KEY,
  ru TEXT NOT NULL,
  kk TEXT,
  namespace TEXT NOT NULL DEFAULT 'app',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS content_pages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug TEXT NOT NULL UNIQUE,
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  body_ru TEXT NOT NULL,
  body_kk TEXT,
  kind TEXT NOT NULL DEFAULT 'info',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS video_views (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  video_id TEXT NOT NULL,
  audience_type TEXT NOT NULL,
  completed BOOLEAN NOT NULL DEFAULT TRUE,
  last_progress_seconds INTEGER NOT NULL DEFAULT 0,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, video_id)
);
CREATE INDEX IF NOT EXISTS idx_video_views_user ON video_views(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS files (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID REFERENCES app_users(id),
  bucket TEXT NOT NULL,
  object_key TEXT NOT NULL,
  mime_type TEXT,
  size_bytes BIGINT,
  public_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_files_bucket_object_key ON files(bucket, object_key);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cleaner_documents_file_id_fkey') THEN
    ALTER TABLE cleaner_documents
      ADD CONSTRAINT cleaner_documents_file_id_fkey
      FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'promotions_banner_file_id_fkey') THEN
    ALTER TABLE promotions
      ADD CONSTRAINT promotions_banner_file_id_fkey
      FOREIGN KEY (banner_file_id) REFERENCES files(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'banners_image_file_id_fkey') THEN
    ALTER TABLE banners
      ADD CONSTRAINT banners_image_file_id_fkey
      FOREIGN KEY (image_file_id) REFERENCES files(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS customer_packages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  legacy_firestore_id TEXT UNIQUE,
  customer_id UUID NOT NULL REFERENCES app_users(id),
  package_id UUID NOT NULL REFERENCES catalog_packages(id),
  address_id UUID REFERENCES customer_addresses(id),
  purchase_payment_id UUID,
  total_cleanings INTEGER NOT NULL,
  available_cleanings INTEGER NOT NULL,
  months INTEGER NOT NULL DEFAULT 1,
  period_start DATE NOT NULL DEFAULT CURRENT_DATE,
  period_end DATE,
  status TEXT NOT NULL DEFAULT 'pending_payment',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE customer_packages ADD COLUMN IF NOT EXISTS freeze_until DATE;

CREATE SEQUENCE IF NOT EXISTS bcc_order_reference_seq START WITH 1000000;

CREATE TABLE IF NOT EXISTS service_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  numeric_id BIGSERIAL UNIQUE,
  legacy_firestore_id TEXT UNIQUE,
  customer_id UUID NOT NULL REFERENCES app_users(id),
  customer_package_id UUID REFERENCES customer_packages(id),
  address_id UUID REFERENCES customer_addresses(id),
  package_id UUID REFERENCES catalog_packages(id),
  cleaner_id UUID REFERENCES app_users(id),
  scheduled_date DATE,
  start_time TIME,
  end_time TIME,
  estimated_duration_minutes INTEGER NOT NULL DEFAULT 0,
  area NUMERIC(10,2),
  status TEXT NOT NULL DEFAULT 'draft',
  base_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  addon_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  bonus_spent NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  payable_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  quality_required BOOLEAN NOT NULL DEFAULT FALSE,
  cancelled_by UUID REFERENCES app_users(id),
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS start_requires_customer_confirmation BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS cleaning_start_confirmed BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS cleaning_start_rejected BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS order_addons (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
  addon_id UUID NOT NULL REFERENCES catalog_addons(id),
  quantity NUMERIC(10,2) NOT NULL DEFAULT 1,
  price NUMERIC(12,2) NOT NULL DEFAULT 0,
  duration_minutes INTEGER NOT NULL DEFAULT 0,
  payment_status payment_status NOT NULL DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_status_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
  old_status TEXT,
  new_status TEXT NOT NULL,
  actor_id UUID REFERENCES app_users(id),
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_offers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
  cleaner_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'offered',
  expires_at TIMESTAMPTZ NOT NULL,
  distance_meters INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(order_id, cleaner_id)
);

CREATE TABLE IF NOT EXISTS preorders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID NOT NULL REFERENCES app_users(id),
  address_id UUID REFERENCES customer_addresses(id),
  package_id UUID REFERENCES catalog_packages(id),
  customer_package_id UUID REFERENCES customer_packages(id),
  desired_date DATE NOT NULL,
  desired_time TEXT,
  area NUMERIC(10,2),
  status preorder_status NOT NULL DEFAULT 'new',
  admin_comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE preorders ADD COLUMN IF NOT EXISTS customer_package_id UUID REFERENCES customer_packages(id);

CREATE TABLE IF NOT EXISTS quality_check_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID NOT NULL REFERENCES app_users(id),
  address_id UUID REFERENCES customer_addresses(id),
  customer_package_id UUID REFERENCES customer_packages(id),
  order_id UUID REFERENCES service_orders(id),
  requested_area NUMERIC(10,2),
  approved_area NUMERIC(10,2),
  scheduled_at TIMESTAMPTZ,
  status quality_status NOT NULL DEFAULT 'pending',
  document_file_id UUID REFERENCES files(id),
  admin_id UUID REFERENCES app_users(id),
  recalculation_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE quality_check_requests ADD COLUMN IF NOT EXISTS customer_package_id UUID REFERENCES customer_packages(id);
ALTER TABLE quality_check_requests ADD COLUMN IF NOT EXISTS admin_comment TEXT;

CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  numeric_id BIGSERIAL UNIQUE,
  legacy_firestore_id TEXT UNIQUE,
  customer_id UUID REFERENCES app_users(id),
  order_id UUID REFERENCES service_orders(id),
  customer_package_id UUID REFERENCES customer_packages(id),
  provider payment_provider NOT NULL,
  status payment_status NOT NULL DEFAULT 'draft',
  amount NUMERIC(12,2) NOT NULL,
  bonus_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  external_id TEXT,
  invoice_phone TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  paid_at TIMESTAMPTZ,
  applied_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE payments ADD COLUMN IF NOT EXISTS applied_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS payment_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
  provider payment_provider NOT NULL,
  event_type TEXT NOT NULL,
  status payment_status,
  external_id TEXT,
  idempotency_key TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider, idempotency_key)
);

ALTER TABLE preorders ADD COLUMN IF NOT EXISTS payment_id UUID REFERENCES payments(id);

CREATE TABLE IF NOT EXISTS promotion_redemptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  promotion_id UUID NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  customer_package_id UUID REFERENCES customer_packages(id) ON DELETE SET NULL,
  payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
  reward_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  once_key TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(promotion_id, payment_id)
);

CREATE TABLE IF NOT EXISTS bonus_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES service_orders(id),
  payment_id UUID REFERENCES payments(id),
  type bonus_type NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  balance_after NUMERIC(12,2) NOT NULL,
  reason_ru TEXT NOT NULL,
  reason_kk TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES app_users(id) ON DELETE CASCADE,
  role app_role,
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  body_ru TEXT NOT NULL,
  body_kk TEXT,
  target_type TEXT,
  target_id TEXT,
  dedupe_key TEXT,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, dedupe_key)
);

CREATE TABLE IF NOT EXISTS notification_reads (
  notification_id UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (notification_id, user_id)
);

CREATE TABLE IF NOT EXISTS chats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type TEXT NOT NULL,
  order_id UUID REFERENCES service_orders(id),
  complaint_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_participants (
  chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ,
  PRIMARY KEY (chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES app_users(id),
  message_ru TEXT,
  message_kk TEXT,
  file_id UUID REFERENCES files(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS complaints (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  numeric_id BIGSERIAL UNIQUE,
  customer_id UUID REFERENCES app_users(id),
  cleaner_id UUID REFERENCES app_users(id),
  order_id UUID REFERENCES service_orders(id),
  status complaint_status NOT NULL DEFAULT 'open',
  title TEXT NOT NULL,
  body TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE complaints
  ADD COLUMN IF NOT EXISTS photo_urls JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE IF NOT EXISTS reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES app_users(id),
  cleaner_id UUID REFERENCES app_users(id),
  order_id UUID REFERENCES service_orders(id),
  rating INTEGER NOT NULL,
  comment TEXT,
  photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS photo_url TEXT,
  ADD COLUMN IF NOT EXISTS positive_traits JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS negative_traits JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE reviews ADD COLUMN IF NOT EXISTS author_role TEXT NOT NULL DEFAULT 'customer';
CREATE INDEX IF NOT EXISTS idx_reviews_order_author ON reviews(order_id,author_role);

CREATE TABLE IF NOT EXISTS checklist_reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
  cleaner_id UUID REFERENCES app_users(id),
  status TEXT NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS checklist_report_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_id UUID NOT NULL REFERENCES checklist_reports(id) ON DELETE CASCADE,
  title_ru TEXT NOT NULL,
  title_kk TEXT,
  checked BOOLEAN NOT NULL DEFAULT FALSE,
  checked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS photo_reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
  cleaner_id UUID REFERENCES app_users(id),
  photo_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(order_id)
);

CREATE INDEX IF NOT EXISTS idx_photo_reports_order ON photo_reports(order_id);

CREATE TABLE IF NOT EXISTS payouts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cleaner_id UUID NOT NULL REFERENCES app_users(id),
  amount NUMERIC(12,2) NOT NULL,
  payout_type TEXT NOT NULL DEFAULT 'manual',
  kaspi_phone TEXT,
  status TEXT NOT NULL DEFAULT 'requested',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE payouts ADD COLUMN IF NOT EXISTS payout_type TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS kaspi_phone TEXT;

CREATE TABLE IF NOT EXISTS legacy_firestore_documents (
  collection_name TEXT NOT NULL,
  document_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  exported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (collection_name, document_id)
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id UUID REFERENCES app_users(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_users_role_created ON app_users(role, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_catalog_packages_import ON catalog_packages(name_ru, cleaning_count, months);
CREATE UNIQUE INDEX IF NOT EXISTS ux_addon_groups_import ON addon_groups(title_ru);
CREATE UNIQUE INDEX IF NOT EXISTS ux_catalog_addons_import ON catalog_addons(title_ru);
CREATE UNIQUE INDEX IF NOT EXISTS ux_service_zones_import ON service_zones(city, name_ru);
CREATE UNIQUE INDEX IF NOT EXISTS ux_connected_houses_import ON connected_houses(city, street_ru, house);
CREATE INDEX IF NOT EXISTS idx_customer_addresses_user ON customer_addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_service_orders_customer ON service_orders(customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_orders_cleaner_time ON service_orders(cleaner_id, scheduled_date, start_time, end_time);
CREATE INDEX IF NOT EXISTS idx_service_orders_status_created ON service_orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status_created ON payments(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_events_payment_created ON payment_events(payment_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bonus_transactions_user ON bonus_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON notifications(user_id, read_at, created_at DESC);
-- Pair with the recipient index for user OR role history/count lookups.
CREATE INDEX IF NOT EXISTS idx_notifications_broadcast_role_created ON notifications(role, created_at DESC) WHERE user_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_role_dedupe ON notifications(role, dedupe_key) WHERE role IS NOT NULL AND dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notification_reads_user ON notification_reads(user_id, read_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user ON chat_participants(user_id, last_read_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_created ON chat_messages(chat_id, created_at);
CREATE INDEX IF NOT EXISTS idx_order_offers_cleaner ON order_offers(cleaner_id, status, expires_at);

-- Mobile backend migration: additive, safe for existing records.
ALTER TABLE app_users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS user_referrals (
  customer_id UUID PRIMARY KEY REFERENCES app_users(id),
  inviter_id UUID NOT NULL REFERENCES app_users(id),
  qualified_at TIMESTAMPTZ,
  reward_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (customer_id <> inviter_id)
);
CREATE INDEX IF NOT EXISTS idx_user_referrals_inviter ON user_referrals(inviter_id);
CREATE TABLE IF NOT EXISTS house_waitlist (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  house_id UUID NOT NULL REFERENCES connected_houses(id),
  user_id UUID NOT NULL REFERENCES app_users(id),
  source TEXT NOT NULL DEFAULT 'app',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(house_id,user_id)
);
CREATE TABLE IF NOT EXISTS training_videos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL,
  audience_type TEXT NOT NULL DEFAULT 'both' CHECK(audience_type IN ('client','cleaner','both')),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  published_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE customer_packages ADD COLUMN IF NOT EXISTS purchase_config JSONB NOT NULL DEFAULT '{}'::jsonb;

INSERT INTO app_settings (key,value) VALUES ('referralBonusAmount','2000'::jsonb), ('referralMilestoneCount','5'::jsonb), ('referralMilestoneBonus','10000'::jsonb) ON CONFLICT (key) DO NOTHING;

INSERT INTO app_settings (key,value) VALUES ('referralDiscountTiers','[{"count":5,"discount":3},{"count":10,"discount":7},{"count":20,"discount":10}]'::jsonb) ON CONFLICT (key) DO NOTHING;

ALTER TABLE training_videos ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT '';

-- City directory: 90 Kazakhstan cities, including Alatau (2024).
-- Source: https://ru.wikipedia.org/wiki/Список_городов_Казахстана (2026-10-06).
CREATE TABLE IF NOT EXISTS city_directory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name_ru TEXT NOT NULL UNIQUE,
  name_kk TEXT NOT NULL,
  region TEXT NOT NULL,
  aliases TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO city_directory(name_ru,name_kk,region,aliases) VALUES
('Абай','Абай','Карагандинская область',ARRAY[]::text[]),
('Акколь','АкколАқкөл','Акмолинская область',ARRAY[]::text[]),
('Аксай','Ақсай','Западно-Казахстанская область',ARRAY[]::text[]),
('Аксу','Ақсу','Павлодарская область',ARRAY[]::text[]),
('Актау','Ақтау','Мангистауская область',ARRAY[]::text[]),
('Актобе','Ақтөбе','Актюбинская область',ARRAY[]::text[]),
('Алатау','Алатау','Алматинская область',ARRAY[]::text[]),
('Алга','Алға','Актюбинская область',ARRAY[]::text[]),
('Алматы','Алматы','Город республиканского значения',ARRAY[]::text[]),
('Алтай','Алтай','Восточно-Казахстанская область',ARRAY['Зыряновск']::text[]),
('Арал','Арал','Кызылординская область',ARRAY['Аральск']::text[]),
('Аркалык','Арқалық','Костанайская область',ARRAY[]::text[]),
('Арыс','Арыс','Туркестанская область',ARRAY[]::text[]),
('Астана','Астана','Город республиканского значения,столица Казахстана',ARRAY['Нур-Султан','Нурсултан']::text[]),
('Атбасар','Атбасар','Акмолинская область',ARRAY[]::text[]),
('Атырау','Атырау','Атырауская область',ARRAY[]::text[]),
('Аягоз','АякозАягөз','Абайская область',ARRAY[]::text[]),
('Байконыр','Байқоңыр','Кызылординская область,арендуется Российской Федерацией[7]',ARRAY['Байконур']::text[]),
('Балхаш','БалкашБалқаш','Карагандинская область',ARRAY[]::text[]),
('Булаево','Булаев','Северо-Казахстанская область',ARRAY[]::text[]),
('Державинск','Державин','Акмолинская область',ARRAY[]::text[]),
('Ерейментау','Ерейментау','Акмолинская область',ARRAY[]::text[]),
('Есик','ЕсыкЕсік','Алматинская область',ARRAY[]::text[]),
('Есиль','ЕсылЕсіл','Акмолинская область',ARRAY[]::text[]),
('Жанаозен','Жаңаөзен','Мангистауская область',ARRAY[]::text[]),
('Жанатас','Жаңатас','Жамбылская область',ARRAY[]::text[]),
('Жаркент','Жаркент','Жетысуская область',ARRAY[]::text[]),
('Жезказган','Жезқазған','Улытауская область',ARRAY[]::text[]),
('Жем','Жем','Актюбинская область',ARRAY[]::text[]),
('Жетысай','ЖетисайЖетісай','Туркестанская область',ARRAY[]::text[]),
('Житикара','ЖитыкараЖітіқара','Костанайская область',ARRAY[]::text[]),
('Зайсан','Зайсаң','Восточно-Казахстанская область',ARRAY[]::text[]),
('Казалинск','КазалыҚазалы','Кызылординская область',ARRAY[]::text[]),
('Кандыагаш','Қандыағаш','Актюбинская область',ARRAY[]::text[]),
('Караганды','Қарағанды','Карагандинская область',ARRAY['Караганда']::text[]),
('Каражал','Қаражал','Улытауская область',ARRAY[]::text[]),
('Каратау','Қаратау','Жамбылская область',ARRAY[]::text[]),
('Каркаралинск','КаркаралыҚарқаралы','Карагандинская область',ARRAY[]::text[]),
('Каскелен','Қаскелең','Алматинская область',ARRAY[]::text[]),
('Кентау','Кентау','Туркестанская область',ARRAY[]::text[]),
('Кокшетау','Көкшетау','Акмолинская область',ARRAY[]::text[]),
('Конаев','Қонаев','Алматинская область',ARRAY['Капчагай','Конаев','Қонаев']::text[]),
('Костанай','Қостанай','Костанайская область',ARRAY[]::text[]),
('Косшы','Қосшы','Акмолинская область',ARRAY['Косши']::text[]),
('Кулсары','Құлсары','Атырауская область',ARRAY['Кульсары']::text[]),
('Курчатов','Курчатов','Абайская область',ARRAY[]::text[]),
('Кызылорда','Қызылорда','Кызылординская область',ARRAY[]::text[]),
('Ленгер','Леңгір','Туркестанская область',ARRAY[]::text[]),
('Лисаковск','Лисаковск','Костанайская область',ARRAY[]::text[]),
('Макинск','Макинск','Акмолинская область',ARRAY[]::text[]),
('Мамлютка','Мамлют','Северо-Казахстанская область',ARRAY[]::text[]),
('Павлодар','Павлодар','Павлодарская область',ARRAY[]::text[]),
('Петропавловск','Петропавл','Северо-Казахстанская область',ARRAY[]::text[]),
('Приозёрск','Приозерск','Карагандинская область',ARRAY['Приозерск']::text[]),
('Риддер','Риддер','Восточно-Казахстанская область',ARRAY[]::text[]),
('Рудный','Рудный','Костанайская область',ARRAY[]::text[]),
('Сарань','Саран','Карагандинская область',ARRAY[]::text[]),
('Сарканд','СаркантСарқант','Жетысуская область',ARRAY[]::text[]),
('Сарыагаш','Сарыағаш','Туркестанская область',ARRAY[]::text[]),
('Сатпаев','СатбаевСәтбаев','Улытауская область',ARRAY[]::text[]),
('Семей','Семей','Абайская область',ARRAY[]::text[]),
('Сергеевка','Сергеев','Северо-Казахстанская область',ARRAY[]::text[]),
('Серебрянск','Серебрянск','Восточно-Казахстанская область',ARRAY[]::text[]),
('Степногорск','Степногорск','Акмолинская область',ARRAY[]::text[]),
('Степняк','Степняк','Акмолинская область',ARRAY[]::text[]),
('Тайынша','Тайынша','Северо-Казахстанская область',ARRAY[]::text[]),
('Талгар','Талғар','Алматинская область',ARRAY[]::text[]),
('Талдыкорган','Талдықорған','Жетысуская область',ARRAY[]::text[]),
('Тараз','Тараз','Жамбылская область',ARRAY[]::text[]),
('Текели','Текелі','Жетысуская область',ARRAY[]::text[]),
('Темир','ТемырТемір','Актюбинская область',ARRAY[]::text[]),
('Темиртау','ТемыртауТеміртау','Карагандинская область',ARRAY[]::text[]),
('Тобыл','Тобыл','Костанайская область',ARRAY[]::text[]),
('Туркестан','ТуркыстанТүркістан','Туркестанская область',ARRAY[]::text[]),
('Уральск','Орал','Западно-Казахстанская область',ARRAY[]::text[]),
('Усть-Каменогорск','ОскеменӨскемен','Восточно-Казахстанская область',ARRAY[]::text[]),
('Ушарал','Үшарал','Жетысуская область',ARRAY[]::text[]),
('Уштобе','Үштөбе','Жетысуская область',ARRAY[]::text[]),
('Форт-Шевченко','Форт-Шевченко','Мангистауская область',ARRAY[]::text[]),
('Хромтау','Хромтау','Актюбинская область',ARRAY[]::text[]),
('Шалкар','Шалқар','Актюбинская область',ARRAY[]::text[]),
('Шар','Шар','Абайская область',ARRAY[]::text[]),
('Шардара','Шардара','Туркестанская область',ARRAY[]::text[]),
('Шахтинск','Шахтинск','Карагандинская область',ARRAY[]::text[]),
('Шемонаиха','Шемонаиха','Восточно-Казахстанская область',ARRAY[]::text[]),
('Шу','Шу','Жамбылская область',ARRAY[]::text[]),
('Шымкент','Шымкент','Город республиканского значения',ARRAY[]::text[]),
('Щучинск','Щучинск','Акмолинская область',ARRAY[]::text[]),
('Экибастуз','Екібастұз','Павлодарская область',ARRAY[]::text[]),
('Эмба','Ембі','Актюбинская область',ARRAY[]::text[])
ON CONFLICT(name_ru) DO NOTHING;

CREATE OR REPLACE FUNCTION domly_normalize_address(value TEXT) RETURNS TEXT
LANGUAGE SQL IMMUTABLE PARALLEL SAFE AS $$
 SELECT trim(regexp_replace(translate(lower(value),'әіңғүұқөһёы','аингуукохеи'),'[^[:alnum:]]+',' ','g'));
$$;

-- Idempotent rewards: repeated approvals cannot credit the same apartment twice.
ALTER TABLE bonus_transactions ADD COLUMN IF NOT EXISTS dedupe_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS bonus_transactions_dedupe_key_unique ON bonus_transactions(dedupe_key) WHERE dedupe_key IS NOT NULL;

-- Moon AI conversations are separate from customer/cleaner order chats.
CREATE TABLE IF NOT EXISTS assistant_installations (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
 key_hash TEXT NOT NULL UNIQUE,
 customer_id UUID REFERENCES app_users(id),
 first_opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 chat_id UUID REFERENCES chats(id)
);
CREATE TABLE IF NOT EXISTS assistant_installation_tokens (
 installation_id UUID NOT NULL REFERENCES assistant_installations(id) ON DELETE CASCADE,
 token TEXT NOT NULL UNIQUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 PRIMARY KEY(installation_id,token)
);
ALTER TABLE chats ADD COLUMN IF NOT EXISTS installation_id UUID REFERENCES assistant_installations(id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_assistant_installation_chat ON chats(installation_id) WHERE type='assistant_guest';

ALTER TABLE chats ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES app_users(id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_assistant_customer_chat ON chats(customer_id) WHERE type='assistant';
ALTER TABLE chat_messages ALTER COLUMN sender_id DROP NOT NULL;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS sender_kind TEXT NOT NULL DEFAULT 'user';
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS external_event_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_external_event ON chat_messages(external_event_id) WHERE external_event_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS moon_ai_outbox (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
 customer_id UUID REFERENCES app_users(id),
 installation_id UUID REFERENCES assistant_installations(id),
 chat_id UUID NOT NULL REFERENCES chats(id),
 payment_id UUID REFERENCES payments(id),
 kind TEXT NOT NULL CHECK(kind IN ('invoice','message','abandoned_checkout','inactive_signup','inactive_install')),
 dedupe_key TEXT NOT NULL UNIQUE,
 payload JSONB NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','processing','sent','cancelled','failed','uncertain')),
 run_after TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 started_at TIMESTAMPTZ,
 finished_at TIMESTAMPTZ,
 provider_thread_id TEXT,
 failure_code TEXT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_moon_ai_pending ON moon_ai_outbox(run_after) WHERE state='pending';
-- Shorten only untouched pending followups; preserve delivered rows and retry schedules.
UPDATE moon_ai_outbox
SET run_after=created_at+INTERVAL '5 minutes',
 payload=jsonb_set(payload,'{text}',to_jsonb(replace(COALESCE(payload->>'text',''),'30 минут','5 минут')))
WHERE kind IN ('inactive_signup','abandoned_checkout') AND state='pending'
 AND started_at IS NULL AND run_after=created_at+INTERVAL '30 minutes';

-- Guests have no WhatsApp phone; they can still ask the in-app assistant first.
UPDATE moon_ai_outbox SET state='cancelled',failure_code='no_whatsapp_phone',finished_at=NOW()
WHERE kind='inactive_install' AND state='pending';

ALTER TABLE payments ADD COLUMN IF NOT EXISTS approval_source TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES app_users(id);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
-- Backfill only records with a recorded approval action or provider event.
UPDATE payments p SET approval_source='manual',
 approved_by=(SELECT a.actor_id FROM audit_logs a WHERE a.entity_id=p.id::text AND a.action='payment.confirmed' AND a.payload->>'source'='admin' ORDER BY a.created_at LIMIT 1),
 approved_at=COALESCE(p.paid_at,p.updated_at)
 WHERE p.status='paid' AND p.approval_source IS NULL AND EXISTS(SELECT 1 FROM audit_logs a WHERE a.entity_id=p.id::text AND a.action='payment.confirmed' AND a.payload->>'source'='admin');
UPDATE payments p SET approval_source=CASE WHEN p.payload ? 'moonAi' THEN 'moon_ai' ELSE p.provider::text END,
 approved_at=COALESCE(p.paid_at,p.updated_at)
 WHERE p.status='paid' AND p.approval_source IS NULL AND (p.provider='bonus' OR p.payload ? 'moonAi' OR EXISTS(SELECT 1 FROM payment_events e WHERE e.payment_id=p.id AND e.status='paid'));

-- Match MooonAI's phone/amount/status/time contract without an external payment ID.
ALTER TABLE payments ADD COLUMN IF NOT EXISTS invoice_requested_at TIMESTAMPTZ;
UPDATE payments SET invoice_requested_at=created_at
 WHERE provider='kaspi' AND invoice_phone IS NOT NULL AND invoice_requested_at IS NULL
 AND status IN ('invoice_requested','paid','rejected','cancelled');
CREATE INDEX IF NOT EXISTS idx_payments_moon_match
 ON payments((regexp_replace(invoice_phone,'[^0-9]','','g')),amount,invoice_requested_at)
 WHERE provider='kaspi';
CREATE TABLE IF NOT EXISTS moon_ai_payment_callbacks (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
 fingerprint TEXT NOT NULL UNIQUE,
 phone TEXT NOT NULL,
 amount NUMERIC(14,2) NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('invoice_sent','paid','rejected','cancelled')),
 event_time TIMESTAMPTZ NOT NULL,
 payment_id UUID REFERENCES payments(id),
 resolution TEXT NOT NULL CHECK(resolution IN ('matched','not_found','ambiguous')),
 candidate_ids UUID[] NOT NULL DEFAULT '{}',
 payload JSONB NOT NULL DEFAULT '{}',
 received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- Restore the payment gate for outstanding, unassigned legacy orders.
WITH corrected AS (
 UPDATE service_orders SET status='pending_payment', updated_at=NOW()
 WHERE status IN ('pending_assignment','waiting_cleaner') AND cleaner_id IS NULL
   AND payable_amount>0
 RETURNING id
), history AS (
 INSERT INTO order_status_history(order_id,new_status,comment)
 SELECT id,'pending_payment','Восстановлено ожидание оплаты неоплаченных допуслуг' FROM corrected
 RETURNING order_id
)
UPDATE order_offers SET status='expired'
 WHERE order_id IN (SELECT order_id FROM history) AND status='offered';


-- Recover missing checkout records without guessing the payer's Kaspi number.
INSERT INTO payments(customer_id,order_id,provider,status,amount,payload)
 SELECT o.customer_id,o.id,'kaspi','pending',o.payable_amount,
   jsonb_build_object('kind','order_payment','recoveredCheckout',true)
 FROM service_orders o
 WHERE o.status='pending_payment' AND o.cleaner_id IS NULL AND o.payable_amount>0
 AND NOT EXISTS(SELECT 1 FROM payments p WHERE p.order_id=o.id);


-- Preserve Kazakh names; populate Russian-script display fallbacks.
CREATE OR REPLACE FUNCTION domly_russian_address(value TEXT) RETURNS TEXT
LANGUAGE SQL IMMUTABLE PARALLEL SAFE AS $$
 SELECT translate(value,'ӘәІіҢңҒғҮүҰұҚқӨөҺһ','АаИиНнГгУуУуКкОоХх');
$$;
UPDATE connected_houses SET street_ru=domly_russian_address(COALESCE(NULLIF(street_ru,''),street_kk)),
 residential_complex_ru=domly_russian_address(COALESCE(NULLIF(residential_complex_ru,''),residential_complex_kk))
 WHERE street_ru IS NULL OR street_ru='' OR street_ru ~ '[ӘәІіҢңҒғҮүҰұҚқӨөҺһ]'
 OR residential_complex_ru ~ '[ӘәІіҢңҒғҮүҰұҚқӨөҺһ]'
 OR (residential_complex_ru IS NULL AND residential_complex_kk IS NOT NULL);

ALTER TABLE app_users ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Cleaner verification contact information (safe to rerun on existing databases).
ALTER TABLE cleaner_profiles ADD COLUMN IF NOT EXISTS home_address TEXT;
ALTER TABLE cleaner_profiles ADD COLUMN IF NOT EXISTS emergency_contact_phone TEXT;
ALTER TABLE cleaner_profiles ADD COLUMN IF NOT EXISTS emergency_contact_relation TEXT;

-- Keep every historical record, but only one live quality review per address.
WITH ranked AS (
 SELECT id, ROW_NUMBER() OVER (
   PARTITION BY customer_id, address_id
   ORDER BY (document_file_id IS NOT NULL) DESC, (status='scheduled') DESC, created_at DESC, id DESC
 ) AS position
 FROM quality_check_requests WHERE status IN ('pending','scheduled')
)
UPDATE quality_check_requests q SET status='cancelled',
 admin_comment=CONCAT_WS(' ', NULLIF(q.admin_comment,''), 'duplicate_auto_closed'), updated_at=NOW()
FROM ranked r WHERE q.id=r.id AND r.position>1;
CREATE UNIQUE INDEX IF NOT EXISTS uq_quality_active_customer_address
 ON quality_check_requests(customer_id, (COALESCE(address_id::text, '')))
 WHERE status IN ('pending','scheduled');

-- Trusted messenger tools: immutable request audit and independently settled adjustments.
CREATE TABLE IF NOT EXISTS bot_area_events (
 event_id TEXT PRIMARY KEY,
 customer_id UUID NOT NULL REFERENCES app_users(id),
 request_hash TEXT NOT NULL,
 result JSONB NOT NULL,
 evidence JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS area_package_adjustments (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
 customer_package_id UUID NOT NULL REFERENCES customer_packages(id),
 event_id TEXT NOT NULL,
 payment_id UUID REFERENCES payments(id),
 bonus_credit NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(bonus_credit>=0),
 old_total NUMERIC(12,2) NOT NULL,
 new_total NUMERIC(12,2) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 UNIQUE(customer_package_id,event_id)
);
ALTER TABLE moon_ai_outbox DROP CONSTRAINT IF EXISTS moon_ai_outbox_kind_check;
ALTER TABLE moon_ai_outbox ADD CONSTRAINT moon_ai_outbox_kind_check
 CHECK(kind IN ('invoice','message','abandoned_checkout','inactive_signup','inactive_install','area_verification'));

-- Persist immediately in the same transaction as the quality-team assignment.
-- No customer files, phone numbers, or documents are copied into chat messages.
CREATE OR REPLACE FUNCTION enqueue_quality_whatsapp() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE assistant_chat UUID;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app_settings WHERE key='qualityAreaBotEnabled' AND value='true'::jsonb) THEN RETURN NEW; END IF;
 IF NEW.status<>'pending' OR NEW.address_id IS NULL OR NEW.document_file_id IS NOT NULL THEN RETURN NEW; END IF;
 IF NOT EXISTS(SELECT 1 FROM customer_addresses WHERE id=NEW.address_id AND user_id=NEW.customer_id AND verified_area IS NULL) THEN RETURN NEW; END IF;
 IF NOT EXISTS(SELECT 1 FROM app_users WHERE id=NEW.customer_id AND role='customer' AND status<>'blocked' AND deleted_at IS NULL AND phone ~ '^\+7[0-9]{10}$') THEN RETURN NEW; END IF;
 INSERT INTO chats(type,customer_id) VALUES('assistant',NEW.customer_id)
 ON CONFLICT(customer_id) WHERE type='assistant' DO UPDATE SET customer_id=EXCLUDED.customer_id RETURNING id INTO assistant_chat;
 INSERT INTO chat_participants(chat_id,user_id) VALUES(assistant_chat,NEW.customer_id) ON CONFLICT DO NOTHING;
 INSERT INTO moon_ai_outbox(customer_id,chat_id,kind,dedupe_key,payload)
 VALUES(NEW.customer_id,assistant_chat,'area_verification','quality-area:'||NEW.id::text,
   jsonb_build_object('qualityCheckId',NEW.id,'text','Требуется подтвердить площадь до уборки. Запросить техплан либо согласовать визит отдела качества.'))
 ON CONFLICT(dedupe_key) DO NOTHING;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS quality_check_whatsapp ON quality_check_requests;
CREATE TRIGGER quality_check_whatsapp AFTER INSERT OR UPDATE OF status ON quality_check_requests
 FOR EACH ROW EXECUTE FUNCTION enqueue_quality_whatsapp();

-- Separate technical control plane. It never trusts application administrator JWTs.
CREATE TABLE IF NOT EXISTS tech_accounts (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), login TEXT NOT NULL UNIQUE,
 password_hash TEXT NOT NULL, display_name TEXT NOT NULL, owner BOOLEAN NOT NULL DEFAULT FALSE,
 permissions TEXT[] NOT NULL DEFAULT '{}', user_scope UUID[], disabled BOOLEAN NOT NULL DEFAULT FALSE,
 must_change_password BOOLEAN NOT NULL DEFAULT TRUE, muted_until TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS tech_sessions (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), account_id UUID NOT NULL REFERENCES tech_accounts(id),
 token_hash TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS tech_login_attempts (
 id BIGSERIAL PRIMARY KEY, identity_hash TEXT NOT NULL, ip_hash TEXT NOT NULL, success BOOLEAN NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS tech_login_identity ON tech_login_attempts(identity_hash,created_at DESC);
CREATE INDEX IF NOT EXISTS tech_login_ip ON tech_login_attempts(ip_hash,created_at DESC);
CREATE TABLE IF NOT EXISTS tech_rules (
 id INTEGER PRIMARY KEY DEFAULT 1 CHECK(id=1), version INTEGER NOT NULL DEFAULT 1,
 config JSONB NOT NULL DEFAULT '{"eventsDays":30,"quarantineDays":14,"auditDays":365,"failedLoginThreshold":8,"deniedThreshold":10,"massOperationThreshold":80,"uploadThreshold":30,"blankDocumentStdDev":1,"blurReject":0.4,"blurReview":12}',
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO tech_rules(id) VALUES(1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS tech_problems (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), fingerprint TEXT NOT NULL UNIQUE,
 kind TEXT NOT NULL DEFAULT 'error', severity TEXT NOT NULL CHECK(severity IN ('info','warning','critical')),
 title TEXT NOT NULL, error_code TEXT, recommendation TEXT NOT NULL,
 first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(), last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(), occurrences BIGINT NOT NULL DEFAULT 0,
 status TEXT NOT NULL DEFAULT 'new' CHECK(status IN ('new','investigating','confirmed','dismissed','fixed')),
 assigned_to UUID REFERENCES tech_accounts(id), confirmed_cause TEXT, hypothesis TEXT,
 fixed_version TEXT, verification_note TEXT, verified_at TIMESTAMPTZ, last_alert_at TIMESTAMPTZ,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS tech_events (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), request_id UUID NOT NULL,
 user_id UUID, user_name TEXT, user_role TEXT, auth_session_id UUID, client_session_id TEXT, operation_id TEXT,
 source TEXT NOT NULL DEFAULT 'server', action TEXT NOT NULL, entity_type TEXT, entity_id TEXT,
 result TEXT NOT NULL DEFAULT 'started' CHECK(result IN ('started','success','failure','interrupted','reported')),
 started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), finished_at TIMESTAMPTZ, duration_ms INTEGER,
 http_status INTEGER, error_code TEXT, user_message TEXT, failure_reason TEXT,
 platform TEXT, app_version TEXT, device TEXT, ip TEXT, gps JSONB,
 fields JSONB NOT NULL DEFAULT '{}'::jsonb, before_values JSONB, after_values JSONB,
 problem_id UUID REFERENCES tech_problems(id), signature TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS tech_events_time ON tech_events(started_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS tech_events_user_time ON tech_events(user_id,started_at,id);
CREATE INDEX IF NOT EXISTS tech_events_session ON tech_events(client_session_id,started_at);
CREATE INDEX IF NOT EXISTS tech_events_operation ON tech_events(operation_id,started_at);
CREATE INDEX IF NOT EXISTS tech_events_request ON tech_events(request_id);
CREATE INDEX IF NOT EXISTS tech_events_entity ON tech_events(entity_type,entity_id,started_at);
CREATE INDEX IF NOT EXISTS tech_events_problem ON tech_events(problem_id,started_at DESC);
CREATE INDEX IF NOT EXISTS tech_events_started ON tech_events(started_at) WHERE result='started';
CREATE TABLE IF NOT EXISTS tech_problem_comments (
 id BIGSERIAL PRIMARY KEY, problem_id UUID NOT NULL REFERENCES tech_problems(id), account_id UUID NOT NULL REFERENCES tech_accounts(id),
 text TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS tech_files (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), file_id UUID REFERENCES files(id) ON DELETE SET NULL,
 event_id UUID REFERENCES tech_events(id) ON DELETE SET NULL, owner_id UUID, entity_type TEXT, entity_id TEXT,
 bucket TEXT NOT NULL, object_key TEXT NOT NULL, mime_type TEXT NOT NULL, size_bytes BIGINT, sha256 TEXT,
 filename TEXT, document_type TEXT NOT NULL DEFAULT 'media',
 decision TEXT NOT NULL CHECK(decision IN ('accepted','manual_review','rejected','unavailable')),
 reason TEXT NOT NULL, analysis JSONB NOT NULL DEFAULT '{}'::jsonb, algorithm_version TEXT NOT NULL,
 rules_version INTEGER NOT NULL, quarantined BOOLEAN NOT NULL DEFAULT FALSE, original_available BOOLEAN NOT NULL DEFAULT TRUE,
 review_status TEXT NOT NULL DEFAULT 'pending', reviewed_by UUID REFERENCES tech_accounts(id), review_note TEXT,
 expires_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(file_id)
);
CREATE INDEX IF NOT EXISTS tech_files_owner ON tech_files(owner_id,created_at DESC);
CREATE INDEX IF NOT EXISTS tech_files_event ON tech_files(event_id);
CREATE INDEX IF NOT EXISTS tech_files_expiry ON tech_files(expires_at) WHERE quarantined=TRUE;
CREATE TABLE IF NOT EXISTS tech_audit (
 seq BIGSERIAL PRIMARY KEY, id UUID NOT NULL DEFAULT uuid_generate_v4(),
 account_id UUID, session_id UUID, action TEXT NOT NULL, target_type TEXT, target_id TEXT,
 result TEXT NOT NULL, payload JSONB NOT NULL, at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
 previous_hash TEXT NOT NULL, entry_hash TEXT NOT NULL
);
CREATE OR REPLACE FUNCTION protect_tech_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF current_setting('domly.tech_archive',TRUE) IS DISTINCT FROM 'on' THEN RAISE EXCEPTION 'technical audit is append-only'; END IF;
 RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS immutable_tech_audit ON tech_audit;
CREATE TRIGGER immutable_tech_audit BEFORE UPDATE OR DELETE ON tech_audit FOR EACH ROW EXECUTE FUNCTION protect_tech_audit();
CREATE TABLE IF NOT EXISTS tech_audit_archives (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), first_seq BIGINT NOT NULL,last_seq BIGINT NOT NULL,
 previous_hash TEXT NOT NULL,last_hash TEXT NOT NULL,sha256 TEXT NOT NULL,object_key TEXT NOT NULL,rows INTEGER NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS tech_notifications (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), account_id UUID NOT NULL REFERENCES tech_accounts(id),
 problem_id UUID REFERENCES tech_problems(id), event_id UUID REFERENCES tech_events(id) ON DELETE SET NULL,
 importance TEXT NOT NULL, title TEXT NOT NULL, dedupe_key TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), acknowledged_at TIMESTAMPTZ, acknowledged_by UUID REFERENCES tech_accounts(id),
 UNIQUE(account_id,dedupe_key)
);
CREATE INDEX IF NOT EXISTS tech_notification_account ON tech_notifications(account_id,created_at DESC);
CREATE TABLE IF NOT EXISTS tech_push_subscriptions (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), account_id UUID NOT NULL REFERENCES tech_accounts(id),
 endpoint_hash TEXT NOT NULL UNIQUE, subscription JSONB NOT NULL, disabled BOOLEAN NOT NULL DEFAULT FALSE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS tech_push_deliveries (
 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), notification_id UUID NOT NULL REFERENCES tech_notifications(id) ON DELETE CASCADE,
 subscription_id UUID NOT NULL REFERENCES tech_push_subscriptions(id) ON DELETE CASCADE,
 status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, next_attempt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 failure_code TEXT, sent_at TIMESTAMPTZ, UNIQUE(notification_id,subscription_id)
);
CREATE TABLE IF NOT EXISTS tech_heartbeats (
 service TEXT PRIMARY KEY, observed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), state JSONB NOT NULL
);
ALTER TABLE app_users ADD COLUMN IF NOT EXISTS auth_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE app_users ADD COLUMN IF NOT EXISTS password_change_required BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE files ADD COLUMN IF NOT EXISTS technical_sha256 TEXT;
ALTER TABLE files ADD COLUMN IF NOT EXISTS technical_quality JSONB;

CREATE INDEX IF NOT EXISTS tech_problems_status ON tech_problems(status,last_seen DESC);
CREATE INDEX IF NOT EXISTS tech_events_source_actor ON tech_events(source,user_id,started_at DESC);
CREATE INDEX IF NOT EXISTS tech_push_pending ON tech_push_deliveries(status,next_attempt);
CREATE INDEX IF NOT EXISTS tech_audit_at ON tech_audit(at,seq);

-- Admin date filters also apply to checklist templates.
ALTER TABLE checklist_templates ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE checklist_report_items ADD COLUMN IF NOT EXISTS required BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE checklist_reports ADD COLUMN IF NOT EXISTS note TEXT NOT NULL DEFAULT '';
CREATE TABLE IF NOT EXISTS api_idempotency (
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, key TEXT NOT NULL, fingerprint TEXT NOT NULL,
  response JSONB, status_code INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), completed_at TIMESTAMPTZ,
  PRIMARY KEY(user_id,scope,key)
);

-- Only claims created by a handler that commits result and mutation together may be recovered.
ALTER TABLE api_idempotency ADD COLUMN IF NOT EXISTS recovery_safe BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE checklist_reports ADD COLUMN IF NOT EXISTS requirements_initialized BOOLEAN NOT NULL DEFAULT FALSE;
