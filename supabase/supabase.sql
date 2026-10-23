-- VỌNG ÂM v4 — 8 sequential cooperative puzzles + a final four-wheel lock.
-- Run this script in Supabase SQL Editor. Browser clients use the public key only.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.game_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  host_name text not null,
  guest_name text,
  host_token_hash text not null,
  guest_token_hash text,
  solved_a boolean not null default false,
  solved_b boolean not null default false,
  hint_to_a text,
  hint_to_b text,
  inventory jsonb not null default '[]'::jsonb,
  log jsonb not null default '["Tiếng đồng hồ vang lên từ nơi không có kim."]'::jsonb,
  final_solved boolean not null default false,
  chapter_step integer not null default 1 check (chapter_step between 1 and 9),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Compatible with an existing V3 table; old active rooms should be considered legacy and not continued.
alter table public.game_rooms add column if not exists chapter_step integer not null default 1;
alter table public.game_rooms add column if not exists solved_a boolean not null default false;
alter table public.game_rooms add column if not exists solved_b boolean not null default false;
alter table public.game_rooms add column if not exists hint_to_a text;
alter table public.game_rooms add column if not exists hint_to_b text;
alter table public.game_rooms add column if not exists inventory jsonb not null default '[]'::jsonb;
alter table public.game_rooms add column if not exists log jsonb not null default '["Tiếng đồng hồ vang lên từ nơi không có kim."]'::jsonb;
alter table public.game_rooms add column if not exists final_solved boolean not null default false;
create index if not exists game_rooms_code_idx on public.game_rooms(code);
create index if not exists game_rooms_created_idx on public.game_rooms(created_at);

create or replace function public.vongam_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists game_rooms_updated_at on public.game_rooms;
create trigger game_rooms_updated_at before update on public.game_rooms for each row execute function public.vongam_updated_at();

alter table public.game_rooms enable row level security;
revoke all on public.game_rooms from anon, authenticated;
drop policy if exists "deny browser access" on public.game_rooms;
create policy "deny browser access" on public.game_rooms for all to anon, authenticated using (false) with check (false);
grant usage on schema public to anon, authenticated;

create or replace function public.get_room_state(p_code text, p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  r public.game_rooms%rowtype;
  v_role text;
  v_owner text;
  v_hint text;
  v_puzzle jsonb;
  v_step integer;
begin
  if p_code is null or p_token is null or length(p_token) < 32 then raise exception 'PHIEN_KHONG_HOP_LE'; end if;
  select * into r from public.game_rooms where code = upper(trim(p_code)) and created_at > now() - interval '24 hours';
  if not found then raise exception 'KHONG_TIM_THAY_PHONG_HOAC_PHONG_HET_HAN'; end if;
  if r.host_token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') then
    v_role := 'A'; v_hint := r.hint_to_a;
  elsif r.guest_token_hash is not null and r.guest_token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') then
    v_role := 'B'; v_hint := r.hint_to_b;
  else raise exception 'PHIEN_KHONG_HOP_LE'; end if;

  v_step := r.chapter_step;
  v_owner := case when v_step between 1 and 8 and v_step % 2 = 1 then 'A'
                  when v_step between 1 and 8 then 'B' else 'AB' end;

  if v_step = 1 then
    v_puzzle := jsonb_build_object('title','Năm hiện vật','location','ĐỒNG HỒ · NGĂN KÉO I','type','RÀNG BUỘC THỨ TỰ',
      'role','NGƯỜI GIỮ BẢN ĐỒ','active',v_role='A','kind','order',
      'lead','Năm biểu tượng đã bị xáo trộn. Dùng tất cả điều kiện để chứng minh chỉ có một thứ tự đúng.',
      'clue',case when v_role='A' then 'Con Mắt đứng ngoài cùng bên trái. Chìa Khóa đứng ngoài cùng bên phải. Ngôi Sao nằm ngay bên phải Mặt Trời. Mặt Trăng nằm bên trái Mặt Trời.' else 'Bản khắc phụ ghi: hai đầu hàng không thể đổi chỗ. Ba vị trí giữa còn lại phải thỏa mãn quan hệ liền kề và trái/phải.' end,
      'helperClue',case when v_role='A' then 'Vai trò còn lại đang quan sát dấu khắc phụ. Hãy hỏi họ điều gì được cố định ở hai đầu hàng.' else 'Bạn đang giữ mảnh bổ trợ. Hãy mô tả dấu khắc hai đầu hàng cho đồng đội.' end,
      'question','Xếp năm hiện vật từ trái sang phải. Sau khi xếp, xác nhận toàn bộ thứ tự.',
      'hints',case when v_role='A' then jsonb_build_array('Cố định Con Mắt ở vị trí 1 và Chìa Khóa ở vị trí 5. Chỉ còn ba vị trí giữa.','Mặt Trời và Ngôi Sao phải liền nhau theo đúng chiều. Mặt Trăng ở bên trái Mặt Trời.') else jsonb_build_array('Hãy biểu diễn các điều kiện bằng năm ô liên tiếp.','Nếu Mặt Trời ở ô 2 thì không còn chỗ cho Mặt Trăng ở bên trái nó; hãy xét vị trí kế tiếp.') end);
  elsif v_step = 2 then
    v_puzzle := jsonb_build_object('title','Bàn phím người gác','location','ĐỒNG HỒ · BÀN PHÍM','type','QUY LUẬT SỐ','role','NGƯỜI GIẢI MÃ','active',v_role='B','kind','choice',
      'lead','Quy luật nằm ở khoảng cách giữa các số, không nằm trong từng số riêng lẻ.',
      'clue',case when v_role='B' then '3 → 8 → 15 → 24 → 35 → ?' else 'Mặt trong nắp đồng hồ: “Đừng nhìn bước nhảy cuối. Hãy nhìn cách các bước nhảy lớn dần.”' end,
      'helperClue',case when v_role='B' then 'Vai trò còn lại nhìn thấy lời nhắn về các bước nhảy. Hãy hỏi họ xem nên so sánh điều gì.' else 'So sánh hiệu số giữa các cặp liên tiếp; chúng tăng đều chứ không ngẫu nhiên.' end,
      'question','Chọn số tiếp theo và giải thích quy luật của hiệu số.',
      'options',jsonb_build_array('46','48','50','52'),
      'hints',case when v_role='B' then jsonb_build_array('Tính lần lượt các hiệu giữa hai số liên tiếp.','Các hiệu là 5, 7, 9, 11. Hiệu tiếp theo tăng thêm 2.') else jsonb_build_array('Hãy hỏi đồng đội về hiệu số thay vì nhìn trực tiếp giá trị.','Hiệu kế tiếp lớn hơn hiệu trước 2 đơn vị.') end);
  elsif v_step = 3 then
    v_puzzle := jsonb_build_object('title','Nhịp đập của con lắc','location','BÀN VIẾT · TỜ GIẤY RÁCH','type','QUY LUẬT NÂNG CAO','role','NGƯỜI GIỮ BẢN ĐỒ','active',v_role='A','kind','text',
      'lead','Các số được khắc theo số nhịp con lắc. Mỗi khoảng cách đều khác nhau, nhưng thay đổi theo một quy luật.',
      'clue',case when v_role='A' then '2 → 5 → 10 → 17 → 26 → ?' else 'Mặt sau tờ giấy: “Bước nhảy là những số lẻ liên tiếp. Đừng cộng vào số đầu.”' end,
      'helperClue',case when v_role='A' then 'Đồng đội có lời ghi chú về dãy số lẻ. Hãy hỏi cách dùng chúng.' else 'Các hiệu lần lượt là những số lẻ liên tiếp; bước nhảy tiếp theo là 11.' end,
      'question','Tìm số tiếp theo. Hãy ghi cả kết quả, không chỉ bước nhảy.',
      'hints',case when v_role='A' then jsonb_build_array('Lấy hiệu: 3, 5, 7, 9.','Hiệu tiếp theo là 11, vì vậy cộng 11 vào 26.') else jsonb_build_array('Tìm khoảng cách giữa các giá trị liên tiếp.','Cộng 11 vào số cuối hiện có.') end);
  elsif v_step = 4 then
    v_puzzle := jsonb_build_object('title','Bản đồ đường cụt','location','BẢN ĐỒ · LỐI ĐI PHÍA ĐÔNG','type','TỌA ĐỘ KHÔNG GIAN','role','NGƯỜI GIẢI MÃ','active',v_role='B','kind','grid',
      'lead','Bản đồ không đánh dấu bằng tên phòng. Theo chỉ dẫn rồi đọc tọa độ theo CỘT trước HÀNG.',
      'clue',case when v_role='B' then 'Bắt đầu tại A1. Đi về phía Đông 2 ô, sau đó đi về phía Nam 2 ô. Cột dùng chữ A–D; hàng dùng số 1–4.' else 'Mép bản đồ: “Mỗi bước chuyển sang ô kế bên. Đi về hướng Nam là tăng số hàng.”' end,
      'helperClue',case when v_role='B' then 'Đồng đội thấy cách đánh dấu hàng và cột. Hãy hỏi cách đọc tọa độ cuối.' else 'Đọc tọa độ theo chữ cột trước rồi tới số hàng. Không tính ô bắt đầu thành một bước.' end,
      'question','Đi đến ô cuối cùng bằng cách nhấn một ô trên bản đồ, rồi xác nhận tọa độ.',
      'hints',case when v_role='B' then jsonb_build_array('Từ A sang Đông hai lần: A → B → C.','Từ hàng 1 xuống Nam hai lần: 1 → 2 → 3.') else jsonb_build_array('Hai bước Đông đổi chữ cột hai lần.','Hai bước Nam tăng số hàng hai đơn vị.') end);
  elsif v_step = 5 then
    v_puzzle := jsonb_build_object('title','Ba chiếc hộp nói dối','location','TỦ KHÓA · BA NGĂN','type','SUY LUẬN LOẠI TRỪ','role','NGƯỜI GIỮ BẢN ĐỒ','active',v_role='A','kind','choice',
      'lead','Chỉ một hộp chứa chìa khóa. Người gác khẳng định chính xác một câu trong ba câu trên nhãn là đúng.',
      'clue',case when v_role='A' then E'GỖ SỒI: “Chìa khóa không ở đây.”\nSẮT: “Chìa khóa ở trong hộp Gỗ Sồi.”\nTHỦY TINH: “Chìa khóa không ở trong hộp Thủy Tinh.”\nChính xác MỘT câu là đúng.' else 'Ghi chú phụ: nếu chìa ở hộp Sồi hoặc hộp Sắt, hai câu sẽ đồng thời đúng. Một giả thuyết còn lại phải làm hai câu sai.' end,
      'helperClue',case when v_role='A' then 'Đồng đội đã loại trừ hai hộp bằng cách đếm số câu đúng. Hãy hỏi họ điều gì xảy ra nếu chìa ở hộp Thủy Tinh.' else 'Nếu chìa ở Sồi: câu 2 và câu 3 đúng. Nếu chìa ở Sắt: câu 1 và câu 3 đúng. Chỉ còn Thủy Tinh.' end,
      'question','Chọn chiếc hộp chứa chìa khóa. Chỉ một giả thuyết khiến đúng một câu khẳng định là sự thật.',
      'options',jsonb_build_array('Gỗ Sồi','Sắt','Thủy Tinh'),
      'hints',case when v_role='A' then jsonb_build_array('Thử từng hộp như một giả thuyết rồi đếm câu đúng.','Hộp Thủy Tinh khiến câu 1 đúng, câu 2 sai và câu 3 sai.') else jsonb_build_array('Với hộp Sồi, câu 2 và 3 cùng đúng.','Với hộp Sắt, câu 1 và 3 cùng đúng.') end);
  elsif v_step = 6 then
    v_puzzle := jsonb_build_object('title','Đĩa chữ lệch ba nấc','location','ĐĨA MẬT MÃ · VÒNG ĐỒNG','type','MẬT MÃ CAESAR','role','NGƯỜI GIẢI MÃ','active',v_role='B','kind','cipher',
      'lead','Mỗi chữ cái đã bị đẩy tiến lên cùng một số bước. Xoay đĩa ngược chiều để đọc dòng ban đầu.',
      'clue',case when v_role='B' then 'FDQGOH' else 'Vết khắc ở mặt sau: “A trở thành D. Muốn tìm chữ gốc, quay ngược lại.”' end,
      'helperClue',case when v_role='B' then 'Vai trò còn lại nhìn thấy hướng xoay của đĩa. Hãy hỏi mã bị đẩy tiến hay lùi.' else 'Mã hóa đẩy chữ tiến 3 vị trí. Khi giải mã, lùi 3 vị trí: D → A.' end,
      'question','Xoay đĩa để thử độ lệch, đọc chuỗi giải mã rồi điền từ tiếng Anh nhận được.',
      'hints',case when v_role='B' then jsonb_build_array('Đĩa bị xoay tiến 3 chữ cái. Khi giải mã, lùi 3: D → A.','Áp dụng cùng cách cho cả sáu chữ. Từ tìm được là một vật có thể phát sáng.') else jsonb_build_array('Hãy dùng chiều ngược với chiều mã hóa.','Dịch mỗi chữ lùi 3 vị trí trong bảng chữ cái.') end);
  elsif v_step = 7 then
    v_puzzle := jsonb_build_object('title','Bộ truyền động ba bánh','location','BỘ BÁNH RĂNG · TRỤC CHÍNH','type','TỈ LỆ TRUYỀN ĐỘNG','role','NGƯỜI GIỮ BẢN ĐỒ','active',v_role='A','kind','gears',
      'lead','Ba bánh răng ăn khớp theo chuỗi. Số răng quyết định số vòng; chiều quay đổi sau mỗi lần ăn khớp.',
      'clue',case when v_role='A' then 'A có 12 răng, B có 18 răng, C có 9 răng. A quay thuận chiều kim đồng hồ 1,5 vòng. Chuỗi ăn khớp A–B–C.' else 'Quy tắc khắc trên trục: số vòng tỉ lệ nghịch với số răng. Hai lần ăn khớp làm C cùng chiều quay với A.' end,
      'helperClue',case when v_role='A' then 'Đồng đội biết quy tắc tỉ lệ nghịch và chiều quay. Hãy hỏi họ vì sao có hai lần đảo chiều.' else 'Số vòng B = 1,5 × 12/18 = 1. Số vòng C = 1 × 18/9 = 2.' end,
      'question','Tính số vòng mà bánh C quay. Có thể kéo thanh trượt để quan sát trước khi trả lời.',
      'hints',case when v_role='A' then jsonb_build_array('Số vòng B = 1,5 × 12/18.','Số vòng C = số vòng B × 18/9.') else jsonb_build_array('Đầu tiên tính số vòng của B.','Sau đó dùng tỷ lệ 18/9 để tính số vòng của C.') end);
  elsif v_step = 8 then
    v_puzzle := jsonb_build_object('title','Mục lục không tên','location','KỆ SÁCH · NGĂN TRÊN CÙNG','type','MÃ SỐ THÀNH CHỮ','role','NGƯỜI GIẢI MÃ','active',v_role='B','kind','letters',
      'lead','Trên gáy sách chỉ còn bốn số. Người lập thư viện dùng quy ước thay chữ cái bằng vị trí của nó trong bảng chữ cái.',
      'clue',case when v_role='B' then E'13 · 15 · 15 · 14\nA = 1, B = 2, C = 3 … Z = 26.' else 'Mép kệ nhắc: “Mỗi số là một chữ riêng. Không cộng chúng lại. Đọc theo thứ tự từ trái sang phải.”' end,
      'helperClue',case when v_role='B' then 'Đồng đội quan sát quy tắc chuyển số sang chữ. Hãy hỏi họ cách ánh xạ các số.' else '13 = M, 15 = O, 14 = N. Hãy đọc liền bốn chữ cái theo đúng thứ tự.' end,
      'question','Chọn bốn chữ cái theo thứ tự để ghép thành từ.',
      'hints',case when v_role='B' then jsonb_build_array('13 = M; 15 = O.','Hai số cuối cũng là 15 và 14. Hãy đọc liền bốn chữ.') else jsonb_build_array('Mỗi số tương ứng vị trí một chữ cái tiếng Anh.','Chữ thứ ba lặp chữ thứ hai; chữ cuối là N.') end);
  else
    v_puzzle := jsonb_build_object('title','Ổ khóa bốn bánh','location','CỬA HẦM · CƠ CHẾ CUỐI','type','TỔNG HỢP MANH MỐI','role','HAI NGƯỜI CÙNG THAO TÁC','active',true,'kind','final',
      'lead','Ghép các mảnh được tìm thấy trong ba cơ chế đầu. Các mảnh khác đã mở đường tới cửa hầm.',
      'clue',case when v_role='A' then 'Bạn đã thấy vị trí của Mặt Trời và dãy số của con lắc. Hãy lấy đúng chữ số được yêu cầu từ mỗi kết quả.' else 'Bạn đã thấy dãy số người gác. Hãy giữ nguyên thứ tự hai chữ số, không sắp xếp chúng lại.' end,
      'helperClue','Hãy nói ra từng mảnh theo thứ tự: vị trí Mặt Trời → kết quả dãy số → chữ số cuối của con lắc.',
      'question','Xoay bốn bánh để kết hợp: vị trí Mặt Trời, hai chữ số của dãy số, rồi chữ số cuối của chuỗi con lắc.');
  end if;

  -- Keep the active clue private to the token's role; the other role receives its complementary observation.
  return jsonb_build_object(
    'gameVersion',4,'code',r.code,'role',v_role,'chapterStep',v_step,'stageOwner',v_owner,'puzzle',v_puzzle,
    'players',jsonb_build_object('A',jsonb_build_object('name',r.host_name),'B',case when r.guest_name is null then null else jsonb_build_object('name',r.guest_name) end),
    'solved',jsonb_build_object('A',r.chapter_step>8,'B',r.chapter_step>8),
    'myHint',v_hint,'inventory',r.inventory,'log',r.log,'finalUnlocked',r.chapter_step=9,'finalSolved',r.final_solved,'updatedAt',r.updated_at);
end; $$;

create or replace function public.create_room(p_name text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_code text; v_token text := encode(extensions.gen_random_bytes(32), 'hex'); v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_created boolean := false; v_attempt integer;
begin
  for v_attempt in 1..12 loop
    v_code := '';
    for i in 1..6 loop v_code := v_code || substr(v_chars, floor(random()*length(v_chars))::integer+1, 1); end loop;
    begin
      insert into public.game_rooms(code,host_name,host_token_hash,chapter_step)
      values(v_code,left(coalesce(nullif(trim(p_name),''),'Người Giữ Bản Đồ'),24),encode(extensions.digest(v_token,'sha256'),'hex'),1);
      v_created:=true; exit;
    exception when unique_violation then v_created:=false;
    end;
  end loop;
  if not v_created then raise exception 'KHONG_TAO_DUOC_PHONG_VUI_LONG_THU_LAI'; end if;
  return jsonb_build_object('code',v_code,'token',v_token,'role','A','state',public.get_room_state(v_code,v_token));
end; $$;

create or replace function public.join_room(p_code text,p_name text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r public.game_rooms%rowtype; v_token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
  select * into r from public.game_rooms where code=upper(trim(p_code)) and created_at>now()-interval '24 hours' for update;
  if not found then raise exception 'KHONG_TIM_THAY_PHONG_HOAC_PHONG_HET_HAN'; end if;
  if r.guest_token_hash is not null then raise exception 'PHONG_DA_DU_HAI_NGUOI'; end if;
  update public.game_rooms set guest_name=left(coalesce(nullif(trim(p_name),''),'Người Giải Mã'),24),guest_token_hash=encode(extensions.digest(v_token,'sha256'),'hex'),log=log||jsonb_build_array('Người Giải Mã đã bước vào tháp.') where id=r.id;
  return jsonb_build_object('code',r.code,'token',v_token,'role','B','state',public.get_room_state(r.code,v_token));
end; $$;

create or replace function public.submit_answer(p_code text,p_token text,p_answer text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r public.game_rooms%rowtype; v_role text; v_owner text; v_answer text; v_name text; v_reward text; v_message text;
begin
  select * into r from public.game_rooms where code=upper(trim(p_code)) and created_at>now()-interval '24 hours' for update;
  if not found then raise exception 'KHONG_TIM_THAY_PHONG_HOAC_PHONG_HET_HAN'; end if;
  if r.guest_token_hash is null then raise exception 'DANG_CHO_DONG_DOI'; end if;
  if r.host_token_hash=encode(extensions.digest(p_token,'sha256'),'hex') then v_role:='A';v_name:=r.host_name;
  elsif r.guest_token_hash=encode(extensions.digest(p_token,'sha256'),'hex') then v_role:='B';v_name:=coalesce(r.guest_name,'Người Giải Mã');
  else raise exception 'PHIEN_KHONG_HOP_LE'; end if;
  if r.final_solved then return public.get_room_state(r.code,p_token); end if;
  if r.chapter_step<1 or r.chapter_step>8 then raise exception 'KHONG_CO_CO_CHE_DANG_CHO'; end if;
  v_owner:=case when r.chapter_step%2=1 then 'A' else 'B' end;
  if v_role<>v_owner then raise exception 'DONG_DOI_DANG_GIU_CO_CHE'; end if;
  v_answer:=regexp_replace(lower(trim(coalesce(p_answer,''))),'\s+','','g');
  case r.chapter_step
    when 1 then if v_answer<>'eye,moon,sun,star,key' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Mảnh khắc I · Mặt Trời ở vị trí thứ 3';v_message:='Mặt Trời ở vị trí 3. Giữ con số này cho ổ khóa cuối.';
    when 2 then if v_answer<>'48' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Mảnh khắc II · Dãy số 48';v_message:='Dãy số kết thúc bằng 48. Hai chữ số này nằm ở giữa ổ khóa cuối.';
    when 3 then if v_answer<>'37' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Mảnh khắc III · Con lắc 37';v_message:='Chuỗi con lắc cho ra 37; chữ số cuối cùng là 7.';
    when 4 then if v_answer<>'c3' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Mảnh bản đồ · C3';v_message:='Đường đi kết thúc tại C3. Một lối cửa nhỏ phía đông đã được ghi vào nhật ký.';
    when 5 then if v_answer<>'thủytinh' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Chìa khóa thủy tinh';v_message:='Chìa khóa nằm trong hộp Thủy Tinh. Tủ phụ mở ra một đĩa mật mã.';
    when 6 then if v_answer<>'candle' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Dòng mã nguyên bản · CANDLE';v_message:='Mã giải ra CANDLE (ngọn nến). Một ngọn nến được thắp lên cạnh bộ bánh răng.';
    when 7 then if v_answer<>'2' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Bánh răng đồng · 2 vòng';v_message:='Trục C hoàn thành 2 vòng. Cửa tủ phía bắc bật chốt.';
    when 8 then if v_answer<>'moon' then raise exception 'SAI_DAP_AN'; end if;
      v_reward:='Trang sách · MOON';v_message:='Từ MOON lặp lại biểu tượng trên mặt đồng hồ. Bốn bánh số cuối đã được nhả chốt.';
  end case;
  update public.game_rooms set chapter_step=chapter_step+1,
    hint_to_a=case when v_role='B' then v_message else hint_to_a end,
    hint_to_b=case when v_role='A' then v_message else hint_to_b end,
    inventory=inventory||jsonb_build_array(v_reward),
    log=log||jsonb_build_array(v_name||' đã mở cơ chế '||r.chapter_step||': '||v_message)
    where id=r.id;
  return public.get_room_state(r.code,p_token);
end; $$;

create or replace function public.submit_final(p_code text,p_token text,p_answer text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r public.game_rooms%rowtype; v_answer text;
begin
  select * into r from public.game_rooms where code=upper(trim(p_code)) and created_at>now()-interval '24 hours' for update;
  if not found then raise exception 'KHONG_TIM_THAY_PHONG_HOAC_PHONG_HET_HAN'; end if;
  if r.host_token_hash<>encode(extensions.digest(p_token,'sha256'),'hex') and (r.guest_token_hash is null or r.guest_token_hash<>encode(extensions.digest(p_token,'sha256'),'hex')) then raise exception 'PHIEN_KHONG_HOP_LE'; end if;
  if r.guest_token_hash is null then raise exception 'DANG_CHO_DONG_DOI'; end if;
  if r.chapter_step<>9 then raise exception 'CHUA_MO_DUOC_O_KHOA_CUOI'; end if;
  if r.final_solved then return public.get_room_state(r.code,p_token); end if;
  v_answer:=regexp_replace(trim(coalesce(p_answer,'')),'\s+','','g');
  if v_answer<>'3487' then raise exception 'SAI_MAT_MA'; end if;
  update public.game_rooms set final_solved=true,inventory=inventory||jsonb_build_array('Cánh cửa tầng hầm'),log=log||jsonb_build_array('Hai người đã ghép đúng mật mã 3487 và mở cửa hầm.') where id=r.id;
  return public.get_room_state(r.code,p_token);
end; $$;

revoke all on function public.get_room_state(text,text) from public;
revoke all on function public.create_room(text) from public;
revoke all on function public.join_room(text,text) from public;
revoke all on function public.submit_answer(text,text,text) from public;
revoke all on function public.submit_final(text,text,text) from public;
grant execute on function public.get_room_state(text,text) to anon,authenticated;
grant execute on function public.create_room(text) to anon,authenticated;
grant execute on function public.join_room(text,text) to anon,authenticated;
grant execute on function public.submit_answer(text,text,text) to anon,authenticated;
grant execute on function public.submit_final(text,text,text) to anon,authenticated;

-- Before a public launch, add edge-level rate limiting, monitoring, cleanup and SQL integration tests.
-- Expire room data periodically if desired: delete from public.game_rooms where created_at < now()-interval '7 days';
