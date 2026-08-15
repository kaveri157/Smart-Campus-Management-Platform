CREATE TYPE public.app_role AS ENUM ('student', 'faculty', 'coordinator', 'admin');
CREATE TYPE public.attendance_status AS ENUM ('present', 'absent', 'late');
CREATE TYPE public.application_status AS ENUM ('applied', 'shortlisted', 'rejected', 'selected');

CREATE OR REPLACE FUNCTION public.touch_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TABLE public.departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  code text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.departments TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.departments TO authenticated;
GRANT ALL ON public.departments TO service_role;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  full_name text NOT NULL DEFAULT '',
  email text NOT NULL DEFAULT '',
  phone text,
  roll_number text,
  department_id uuid REFERENCES public.departments ON DELETE SET NULL,
  semester int,
  skills text[] NOT NULL DEFAULT '{}',
  linkedin_url text,
  github_url text,
  resume_url text,
  avatar_url text,
  bio text,
  cgpa numeric(4,2),
  is_approved boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER profiles_touch BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.is_staff(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('faculty','coordinator','admin'));
$$;

CREATE OR REPLACE FUNCTION public.can_manage_campus(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('coordinator','admin'));
$$;

CREATE POLICY "departments readable" ON public.departments FOR SELECT TO authenticated USING (true);
CREATE POLICY "departments managed by admin" ON public.departments FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "profiles own read" ON public.profiles FOR SELECT TO authenticated USING (id = auth.uid() OR public.is_staff(auth.uid()));
CREATE POLICY "profiles own update" ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE POLICY "profiles admin write" ON public.profiles FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "roles own read" ON public.user_roles FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff(auth.uid()));

CREATE TABLE public.courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  title text NOT NULL,
  department_id uuid REFERENCES public.departments ON DELETE SET NULL,
  semester int NOT NULL DEFAULT 1,
  credits int NOT NULL DEFAULT 4,
  faculty_id uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.courses TO authenticated;
GRANT ALL ON public.courses TO service_role;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "courses readable" ON public.courses FOR SELECT TO authenticated USING (true);
CREATE POLICY "courses managed" ON public.courses FOR ALL TO authenticated
  USING (public.can_manage_campus(auth.uid())) WITH CHECK (public.can_manage_campus(auth.uid()));

CREATE TABLE public.clubs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  description text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT 'general',
  lead_id uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clubs TO authenticated;
GRANT ALL ON public.clubs TO service_role;
ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clubs readable" ON public.clubs FOR SELECT TO authenticated USING (true);
CREATE POLICY "clubs managed" ON public.clubs FOR ALL TO authenticated
  USING (public.can_manage_campus(auth.uid())) WITH CHECK (public.can_manage_campus(auth.uid()));

CREATE TABLE public.club_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (club_id, user_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.club_members TO authenticated;
GRANT ALL ON public.club_members TO service_role;
ALTER TABLE public.club_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "club members read" ON public.club_members FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff(auth.uid()));
CREATE POLICY "club members join" ON public.club_members FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "club members leave" ON public.club_members FOR DELETE TO authenticated USING (user_id = auth.uid() OR public.can_manage_campus(auth.uid()));

CREATE TABLE public.attendance_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.courses ON DELETE CASCADE,
  faculty_id uuid REFERENCES auth.users ON DELETE SET NULL,
  session_date date NOT NULL DEFAULT current_date,
  topic text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance_sessions TO authenticated;
GRANT ALL ON public.attendance_sessions TO service_role;
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sessions readable" ON public.attendance_sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "sessions managed" ON public.attendance_sessions FOR ALL TO authenticated
  USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()));

CREATE TABLE public.attendance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.attendance_sessions ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  status public.attendance_status NOT NULL DEFAULT 'present',
  marked_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance_records TO authenticated;
GRANT ALL ON public.attendance_records TO service_role;
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "attendance own read" ON public.attendance_records FOR SELECT TO authenticated USING (student_id = auth.uid() OR public.is_staff(auth.uid()));
CREATE POLICY "attendance staff write" ON public.attendance_records FOR ALL TO authenticated
  USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()));

CREATE TABLE public.assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.courses ON DELETE CASCADE,
  faculty_id uuid REFERENCES auth.users ON DELETE SET NULL,
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  rubric text,
  attachment_url text,
  max_marks int NOT NULL DEFAULT 100,
  deadline timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.assignments TO authenticated;
GRANT ALL ON public.assignments TO service_role;
ALTER TABLE public.assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "assignments readable" ON public.assignments FOR SELECT TO authenticated USING (true);
CREATE POLICY "assignments staff write" ON public.assignments FOR ALL TO authenticated
  USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()));

CREATE TABLE public.assignment_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES public.assignments ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  file_url text,
  github_url text,
  notes text,
  is_late boolean NOT NULL DEFAULT false,
  marks int,
  feedback text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  UNIQUE (assignment_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.assignment_submissions TO authenticated;
GRANT ALL ON public.assignment_submissions TO service_role;
ALTER TABLE public.assignment_submissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "submissions own read" ON public.assignment_submissions FOR SELECT TO authenticated USING (student_id = auth.uid() OR public.is_staff(auth.uid()));
CREATE POLICY "submissions own insert" ON public.assignment_submissions FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
CREATE POLICY "submissions own update" ON public.assignment_submissions FOR UPDATE TO authenticated USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());
CREATE POLICY "submissions staff grade" ON public.assignment_submissions FOR UPDATE TO authenticated
  USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()));

CREATE TABLE public.events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT 'general',
  venue text NOT NULL DEFAULT '',
  banner_url text,
  speakers text[] NOT NULL DEFAULT '{}',
  seats int NOT NULL DEFAULT 100,
  starts_at timestamptz NOT NULL,
  registration_deadline timestamptz NOT NULL,
  created_by uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.events TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.events TO authenticated;
GRANT ALL ON public.events TO service_role;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events public read" ON public.events FOR SELECT USING (true);
CREATE POLICY "events managed" ON public.events FOR ALL TO authenticated
  USING (public.can_manage_campus(auth.uid())) WITH CHECK (public.can_manage_campus(auth.uid()));

CREATE TABLE public.event_registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  ticket_code text NOT NULL UNIQUE DEFAULT upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
  registered_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.event_registrations TO authenticated;
GRANT ALL ON public.event_registrations TO service_role;
ALTER TABLE public.event_registrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "registrations own read" ON public.event_registrations FOR SELECT TO authenticated USING (student_id = auth.uid() OR public.is_staff(auth.uid()));
CREATE POLICY "registrations own insert" ON public.event_registrations FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
CREATE POLICY "registrations own delete" ON public.event_registrations FOR DELETE TO authenticated USING (student_id = auth.uid() OR public.can_manage_campus(auth.uid()));

CREATE TABLE public.placements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company text NOT NULL,
  role_title text NOT NULL,
  description text NOT NULL DEFAULT '',
  ctc text NOT NULL DEFAULT '',
  location text NOT NULL DEFAULT '',
  eligibility text NOT NULL DEFAULT '',
  min_cgpa numeric(4,2),
  deadline timestamptz NOT NULL,
  created_by uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.placements TO authenticated;
GRANT ALL ON public.placements TO service_role;
ALTER TABLE public.placements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "placements readable" ON public.placements FOR SELECT TO authenticated USING (true);
CREATE POLICY "placements managed" ON public.placements FOR ALL TO authenticated
  USING (public.can_manage_campus(auth.uid())) WITH CHECK (public.can_manage_campus(auth.uid()));

CREATE TABLE public.placement_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  placement_id uuid NOT NULL REFERENCES public.placements ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  resume_url text,
  status public.application_status NOT NULL DEFAULT 'applied',
  applied_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (placement_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.placement_applications TO authenticated;
GRANT ALL ON public.placement_applications TO service_role;
ALTER TABLE public.placement_applications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "applications own read" ON public.placement_applications FOR SELECT TO authenticated USING (student_id = auth.uid() OR public.is_staff(auth.uid()));
CREATE POLICY "applications own insert" ON public.placement_applications FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
CREATE POLICY "applications own delete" ON public.placement_applications FOR DELETE TO authenticated USING (student_id = auth.uid());
CREATE POLICY "applications staff update" ON public.placement_applications FOR UPDATE TO authenticated
  USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()));

CREATE TABLE public.announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  audience text NOT NULL DEFAULT 'all',
  is_pinned boolean NOT NULL DEFAULT false,
  author_id uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.announcements TO authenticated;
GRANT ALL ON public.announcements TO service_role;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "announcements readable" ON public.announcements FOR SELECT TO authenticated USING (true);
CREATE POLICY "announcements staff write" ON public.announcements FOR ALL TO authenticated
  USING (public.is_staff(auth.uid())) WITH CHECK (public.is_staff(auth.uid()));

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT 'system',
  link text,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notifications own read" ON public.notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "notifications own update" ON public.notifications FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "notifications own delete" ON public.notifications FOR DELETE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "notifications staff insert" ON public.notifications FOR INSERT TO authenticated WITH CHECK (public.is_staff(auth.uid()));

CREATE TABLE public.activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES auth.users ON DELETE SET NULL,
  action text NOT NULL,
  entity text NOT NULL DEFAULT '',
  details jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.activity_logs TO authenticated;
GRANT ALL ON public.activity_logs TO service_role;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "logs admin read" ON public.activity_logs FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE TABLE public.user_settings (
  user_id uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  theme text NOT NULL DEFAULT 'dark',
  email_notifications boolean NOT NULL DEFAULT true,
  push_notifications boolean NOT NULL DEFAULT false,
  profile_visibility text NOT NULL DEFAULT 'campus',
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_settings TO authenticated;
GRANT ALL ON public.user_settings TO service_role;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "settings own" ON public.user_settings FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE TRIGGER settings_touch BEFORE UPDATE ON public.user_settings FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.email, ''),
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_settings (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'student') ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

INSERT INTO public.departments (name, code) VALUES
  ('Computer Engineering', 'CMP'),
  ('Information Technology', 'IT'),
  ('Electronics & Telecommunication', 'ENTC'),
  ('Mechanical Engineering', 'MECH'),
  ('Civil Engineering', 'CIVIL');

INSERT INTO public.courses (code, title, department_id, semester, credits)
SELECT v.code, v.title, d.id, v.semester, v.credits
FROM (VALUES
  ('CMP301', 'Data Structures and Algorithms', 'CMP', 5, 4),
  ('CMP302', 'Operating Systems', 'CMP', 5, 4),
  ('CMP303', 'Database Management Systems', 'CMP', 5, 3),
  ('IT301', 'Computer Networks', 'IT', 5, 4),
  ('IT302', 'Web Technologies', 'IT', 5, 3),
  ('ENTC201', 'Signals and Systems', 'ENTC', 3, 4),
  ('MECH201', 'Thermodynamics', 'MECH', 3, 4),
  ('CIVIL201', 'Structural Analysis', 'CIVIL', 3, 4)
) AS v(code, title, dept, semester, credits)
JOIN public.departments d ON d.code = v.dept;

INSERT INTO public.clubs (name, description, category) VALUES
  ('Coding Club', 'Weekly contests, open-source sprints and interview prep circles.', 'technical'),
  ('Robotics Society', 'Line followers, drones and the annual campus robowars.', 'technical'),
  ('Literary Circle', 'Debates, open mics and the quarterly campus magazine.', 'cultural'),
  ('Sports Council', 'Inter-department leagues and the winter athletics meet.', 'sports');

INSERT INTO public.events (title, description, category, venue, seats, starts_at, registration_deadline, speakers) VALUES
  ('DevFusion Hackathon Bootcamp', 'A two-day build sprint with mentors from product companies. Bring a laptop and a rough idea.', 'technical', 'Main Auditorium', 240, now() + interval '9 days', now() + interval '6 days', ARRAY['Neha Kulkarni','Arjun Rao']),
  ('Placement Readiness Workshop', 'Resume teardown, aptitude drills and a mock technical interview round.', 'placement', 'Seminar Hall B', 120, now() + interval '4 days', now() + interval '2 days', ARRAY['Training & Placement Cell']),
  ('Robotics Expo', 'Final-year robotics projects on display, judged by an industry panel.', 'technical', 'Workshop Block', 180, now() + interval '17 days', now() + interval '13 days', ARRAY['Dr. S. Iyer']),
  ('Annual Cultural Night', 'Music, drama and the closing dance showcase for the academic year.', 'cultural', 'Open Air Theatre', 600, now() + interval '25 days', now() + interval '20 days', ARRAY['Cultural Committee']);

INSERT INTO public.placements (company, role_title, description, ctc, location, eligibility, min_cgpa, deadline) VALUES
  ('Nexora Systems', 'Software Engineer Trainee', 'Backend focused role working on distributed billing services. Six month training followed by team allocation.', '8.5 LPA', 'Pune', 'B.E. CMP / IT, 2026 batch, no active backlogs', 7.00, now() + interval '11 days'),
  ('Brightline Analytics', 'Data Analyst', 'SQL heavy analytics role supporting retail forecasting dashboards.', '6.2 LPA', 'Bengaluru', 'Any branch, 2026 batch', 6.50, now() + interval '7 days'),
  ('Halcyon Robotics', 'Embedded Engineer', 'Firmware work on motor controllers and sensor fusion pipelines.', '7.4 LPA', 'Hyderabad', 'ENTC / MECH, 2026 batch', 6.75, now() + interval '15 days'),
  ('Fieldstone Infra', 'Graduate Site Engineer', 'Site execution and quality auditing on metro infrastructure projects.', '5.5 LPA', 'Nagpur', 'CIVIL, 2026 batch', 6.00, now() + interval '20 days');

INSERT INTO public.announcements (title, body, audience, is_pinned) VALUES
  ('Mid-semester exam timetable published', 'The mid-semester timetable for all fifth semester branches is now on the notice board and the portal. Report fifteen minutes before each slot.', 'all', true),
  ('Library extended hours during exams', 'The central library will stay open until 11 PM from Monday. Carry your ID card for late entry.', 'student', false),
  ('Faculty: submit internal marks by Friday', 'Internal assessment marks for all fifth semester courses must be uploaded before Friday 5 PM.', 'faculty', false);