import Foundation

/// All user-facing strings. Thai is the development language; keys are the Thai source text so the
/// String Catalog can add translations later.
enum L10n {
    enum Common {
        static var ok: String { String(localized: "ตกลง") }
        static var cancel: String { String(localized: "ยกเลิก") }
        static var close: String { String(localized: "ปิด") }
        static var retry: String { String(localized: "ลองอีกครั้ง") }
        static var save: String { String(localized: "บันทึก") }
        static var done: String { String(localized: "เสร็จ") }
        static var send: String { String(localized: "ส่ง") }
        static var unnamedPlace: String { String(localized: "สถานที่ไม่มีชื่อ") }
        static var openSettings: String { String(localized: "เปิดการตั้งค่า") }
        static var somethingWentWrong: String { String(localized: "เกิดข้อผิดพลาด ลองใหม่อีกครั้ง") }
        static var directions: String { String(localized: "เส้นทาง") }
        static var remove: String { String(localized: "ลบ") }
        static var optional: String { String(localized: "ไม่บังคับ") }
        static var loading: String { String(localized: "กำลังโหลด…") }
        static var demoBadge: String { String(localized: "โหมดสาธิต") }
    }

    enum Category {
        static var all: String { String(localized: "ทั้งหมด") }
        static var cafe: String { String(localized: "คาเฟ่") }
        static var library: String { String(localized: "ห้องสมุด") }
        static var coworking: String { String(localized: "Co-working") }
        static var studySpace: String { String(localized: "Study Space") }
        static var other: String { String(localized: "อื่น ๆ") }
    }

    enum Rating {
        static var noReviews: String { String(localized: "ยังไม่มีรีวิว") }
        static func summary(_ average: String, _ count: Int) -> String { String(localized: "\(average) · \(count) รีวิว") }
        static func accessibility(_ average: String, _ count: Int) -> String { String(localized: "คะแนนเฉลี่ย \(average) จาก 5 จาก \(count) รีวิว") }
        static func reviewCount(_ count: Int) -> String { String(localized: "\(count) รีวิว") }
        static func starLabel(_ star: Int) -> String {
            switch star {
            case 1: String(localized: "1 ดาว · แย่")
            case 2: String(localized: "2 ดาว · ต่ำกว่าที่คาด")
            case 3: String(localized: "3 ดาว · พอใช้")
            case 4: String(localized: "4 ดาว · ดี")
            default: String(localized: "5 ดาว · ยอดเยี่ยม")
            }
        }
    }

    enum Explore {
        static var title: String { String(localized: "สำรวจ") }
        static var searchPlaceholder: String { String(localized: "ค้นหาคาเฟ่ ห้องสมุด ที่อ่านหนังสือ…") }
        static var filter: String { String(localized: "ตัวกรอง") }
        static var viewList: String { String(localized: "รายการ") }
        static var viewMap: String { String(localized: "แผนที่") }
        static var searchThisArea: String { String(localized: "ค้นหาบริเวณนี้") }
        static var locateMe: String { String(localized: "ตำแหน่งของฉัน") }
        static var nearYou: String { String(localized: "ใกล้คุณ") }
        static var defaultArea: String { String(localized: "สยาม กรุงเทพฯ · แตะเพื่อใช้ตำแหน่งของคุณ") }
        static var locating: String { String(localized: "กำลังหาตำแหน่ง…") }
        static var mapArea: String { String(localized: "บริเวณบนแผนที่") }
        static var locationOff: String { String(localized: "ปิดตำแหน่งอยู่ · ค้นหาตามชื่อหรือแผนที่ได้") }
        static var recommended: String { String(localized: "แนะนำในบริเวณนี้") }
        static var recommendedSubtitle: String { String(localized: "จัดอันดับจากคะแนนรีวิว จำนวนรีวิว และระยะทาง") }
        static var results: String { String(localized: "ผลการค้นหา") }
        static func resultsCount(_ count: Int) -> String { String(localized: "\(count) แห่งบน Nanglen") }
        static var searching: String { String(localized: "กำลังค้นหา…") }
        static var emptyTitle: String { String(localized: "ยังไม่พบสถานที่บน Nanglen") }
        static var emptyMessage: String { String(localized: "ลองคำค้นอื่น ขยายระยะทาง หรือแนะนำสถานที่ใหม่ให้ชุมชน") }
        static var addPlace: String { String(localized: "เพิ่มสถานที่ใหม่") }
        static var missingPlaceFooter: String { String(localized: "ไม่เจอที่ที่หา? แนะนำสถานที่ใหม่ ทีมงานจะตรวจสอบก่อนเผยแพร่") }
        static var errorTitle: String { String(localized: "โหลดข้อมูลไม่สำเร็จ") }
        static var offlineBanner: String { String(localized: "ออฟไลน์ · แสดงข้อมูลที่บันทึกไว้ อาจไม่เป็นปัจจุบัน") }
        static func offlineSince(_ relative: String) -> String { String(localized: "ออฟไลน์ · ข้อมูลที่บันทึกไว้เมื่อ \(relative) อาจไม่เป็นปัจจุบัน") }
        static var loadMore: String { String(localized: "โหลดเพิ่ม") }
        static var locationDeniedTitle: String { String(localized: "ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง") }
        static var locationDeniedMessage: String { String(localized: "เปิดสิทธิ์ตำแหน่งในการตั้งค่าเพื่อค้นหาสถานที่ใกล้คุณ หรือค้นหาตามชื่อได้เลย") }
    }

    enum Filter {
        static var title: String { String(localized: "ตัวกรอง") }
        static var sort: String { String(localized: "เรียงตาม") }
        static var sortRelevance: String { String(localized: "เหมาะสมที่สุด") }
        static var sortDistance: String { String(localized: "ใกล้ที่สุด") }
        static var sortRating: String { String(localized: "คะแนนสูง") }
        static var distance: String { String(localized: "ระยะทาง") }
        static var minimumRating: String { String(localized: "คะแนนขั้นต่ำ") }
        static var any: String { String(localized: "ทั้งหมด") }
        static var apply: String { String(localized: "ดูผลลัพธ์") }
        static var reset: String { String(localized: "รีเซ็ต") }
        static var footnote: String { String(localized: "คะแนนเฉลี่ยมาจากรีวิวที่ยืนยันการไปจริง การจัดอันดับคำนึงถึงจำนวนรีวิวด้วย สถานที่ที่จ่ายเงินไม่ได้รับอันดับพิเศษ") }
    }

    enum Detail {
        static var writeReview: String { String(localized: "เขียนรีวิว") }
        static var updateReview: String { String(localized: "อัปเดตรีวิว") }
        static var save: String { String(localized: "บันทึกสถานที่") }
        static var unsave: String { String(localized: "เลิกบันทึก") }
        static var communityTags: String { String(localized: "ผู้มาเยือนบอกว่า") }
        static var communityTagsNote: String { String(localized: "จากรีวิวของผู้ใช้ ไม่ใช่ข้อมูลยืนยันจากสถานที่") }
        static var reviews: String { String(localized: "รีวิว") }
        static var sortRelevant: String { String(localized: "เกี่ยวข้อง") }
        static var sortRecent: String { String(localized: "ล่าสุด") }
        static var noReviewsMessage: String { String(localized: "เป็นคนแรกที่รีวิวหลังจากไปถึงสถานที่จริง") }
        static var verifiedVisit: String { String(localized: "ยืนยันการไปจริง") }
        static var you: String { String(localized: "คุณ") }
        static var info: String { String(localized: "ข้อมูลสถานที่") }
        static var address: String { String(localized: "ที่อยู่") }
        static var website: String { String(localized: "เว็บไซต์") }
        static var phone: String { String(localized: "โทร") }
        static var sourceCommunity: String { String(localized: "ข้อมูลจากผู้แนะนำสถานที่ ตรวจสอบโดยทีมงาน") }
        static var sourceBusiness: String { String(localized: "ข้อมูลจากเจ้าของสถานที่ที่ยืนยันแล้ว") }
        static var sourceCurated: String { String(localized: "ข้อมูลจากทีมงาน Nanglen") }
        static var claim: String { String(localized: "เป็นเจ้าของที่นี่? ขอยืนยันความเป็นเจ้าของ") }
        static var managedByYou: String { String(localized: "คุณเป็นผู้ดูแลสถานที่นี้") }
        static var report: String { String(localized: "รายงานรีวิว") }
        static var reportSent: String { String(localized: "ส่งรายงานแล้ว ทีมงานจะตรวจสอบ") }
        static var temporarilyClosed: String { String(localized: "ปิดชั่วคราว") }
        static var permanentlyClosed: String { String(localized: "ปิดถาวร") }
        static var myReviewHidden: String { String(localized: "รีวิวของคุณถูกซ่อนโดยทีมงาน") }
        static func myReviewSummary(_ rating: Int, _ relative: String) -> String { String(localized: "รีวิวของคุณ \(rating)★ · \(relative)") }
        static var revisitHint: String { String(localized: "อัปเดตรีวิวได้หลังยืนยันการไปครั้งใหม่") }
        static var photosPending: String { String(localized: "รูปภาพจะแสดงหลังผ่านการตรวจสอบ") }
    }

    enum Review {
        static var title: String { String(localized: "เขียนรีวิว") }
        static var explain: String { String(localized: "เพื่อให้รีวิวบน Nanglen น่าเชื่อถือ เราจะยืนยันว่าคุณอยู่ที่สถานที่นี้") }
        static var checking: String { String(localized: "กำลังตรวจสอบตำแหน่ง…") }
        static var askingPermission: String { String(localized: "ขออนุญาตใช้ตำแหน่งขณะใช้แอป") }
        static var verifying: String { String(localized: "กำลังยืนยันกับเซิร์ฟเวอร์…") }
        static var verified: String { String(localized: "ยืนยันการไปจริงแล้ว") }
        static func tooFar(_ distance: String) -> String { String(localized: "คุณอยู่ห่างจากสถานที่ประมาณ \(distance) ต้องอยู่ภายในรัศมีที่กำหนด") }
        static var tooFarGeneric: String { String(localized: "คุณอยู่ไกลจากสถานที่เกินไป") }
        static var inaccurate: String { String(localized: "ตำแหน่งยังไม่แม่นยำพอ ลองขยับไปใกล้หน้าต่างหรือที่โล่งแล้วลองใหม่") }
        static var stale: String { String(localized: "ตำแหน่งที่ได้ไม่เป็นปัจจุบัน ลองใหม่อีกครั้ง") }
        static var unavailable: String { String(localized: "หาตำแหน่งไม่ได้ในตอนนี้ ลองใหม่อีกครั้ง") }
        static var permissionDenied: String { String(localized: "ต้องเปิดสิทธิ์ตำแหน่งเพื่อยืนยันการไปจริง") }
        static var registrationRequired: String { String(localized: "ต้องยืนยันเบอร์โทรก่อนเขียนรีวิว") }
        static var spoofDisclaimer: String { String(localized: "การยืนยันใช้ตำแหน่ง GPS ของอุปกรณ์ เราไม่เก็บประวัติตำแหน่งของคุณ") }
        static var rating: String { String(localized: "ให้คะแนนโดยรวม") }
        static var ratingRequired: String { String(localized: "เลือกคะแนน 1–5 ดาว") }
        static var purpose: String { String(localized: "มาทำอะไร?") }
        static var tags: String { String(localized: "อะไรโดดเด่น? (เลือกได้ 3)") }
        static var comment: String { String(localized: "ความคิดเห็นสั้น ๆ") }
        static var commentPlaceholder: String { String(localized: "อะไรที่คนอื่นควรรู้ก่อนมา?") }
        static var photos: String { String(localized: "รูปภาพ (สูงสุด 3)") }
        static var addPhoto: String { String(localized: "เพิ่มรูป") }
        static var submit: String { String(localized: "เผยแพร่รีวิว") }
        static var submitting: String { String(localized: "กำลังเผยแพร่…") }
        static var published: String { String(localized: "เผยแพร่รีวิวแล้ว ขอบคุณ!") }
        static var updated: String { String(localized: "อัปเดตรีวิวแล้ว") }
        static func photosFailed(_ count: Int) -> String { String(localized: "อัปโหลดรูปไม่สำเร็จ \(count) รูป รีวิวถูกเผยแพร่แล้ว") }
        static var photosPending: String { String(localized: "รูปภาพจะแสดงหลังผ่านการตรวจสอบ") }
        static var draftSaved: String { String(localized: "บันทึกฉบับร่างไว้ในเครื่องแล้ว ยังไม่ได้เผยแพร่") }
        static var draftRestored: String { String(localized: "นำฉบับร่างที่ยังไม่ส่งกลับมาแล้ว") }
        static var reverify: String { String(localized: "การยืนยันหมดอายุหรือถูกใช้ไปแล้ว ยืนยันตำแหน่งใหม่ก่อนเผยแพร่") }
        static func characters(_ count: Int, _ max: Int) -> String { String(localized: "\(count)/\(max)") }
        static var tooManyTags: String { String(localized: "เลือกได้สูงสุด 3 แท็ก") }
        static var verifyAgain: String { String(localized: "ยืนยันตำแหน่งอีกครั้ง") }
    }

    enum Purpose {
        static var study: String { String(localized: "อ่านหนังสือ") }
        static var work: String { String(localized: "ทำงาน") }
        static var meeting: String { String(localized: "ประชุม") }
        static var relax: String { String(localized: "พักผ่อน") }
        static var other: String { String(localized: "อื่น ๆ") }
    }

    enum Account {
        static var guestTitle: String { String(localized: "ผู้เยี่ยมชม") }
        static var guestMessage: String { String(localized: "ใช้งานได้ทันทีโดยไม่ต้องสมัคร รายการที่บันทึกไว้ผูกกับอุปกรณ์นี้ หากลบแอปหรือเปลี่ยนเครื่องอาจหายได้") }
        static var linkPhone: String { String(localized: "ยืนยันเบอร์โทรศัพท์") }
        static var linkPhoneBenefit: String { String(localized: "ยืนยันเบอร์เพื่อเขียนรีวิว แนะนำสถานที่ และเก็บรายการที่บันทึกไว้ข้ามอุปกรณ์ ข้อมูลเดิมของคุณจะยังอยู่ครบ") }
        static var phonePlaceholder: String { String(localized: "เบอร์โทรศัพท์ เช่น 081 234 5678") }
        static var sendCode: String { String(localized: "ส่งรหัส OTP") }
        static var codePlaceholder: String { String(localized: "รหัส 6 หลัก") }
        static var verifyCode: String { String(localized: "ยืนยันรหัส") }
        static func codeSent(_ masked: String) -> String { String(localized: "ส่งรหัสไปที่ \(masked) แล้ว") }
        static var linked: String { String(localized: "ยืนยันเบอร์โทรเรียบร้อย คุณเป็นสมาชิกแล้ว") }
        static func demoOTPHint(_ code: String) -> String { String(localized: "โหมดสาธิต: ไม่มีการส่ง SMS จริง ใช้รหัส \(code)") }
        static var invalidPhone: String { String(localized: "รูปแบบเบอร์โทรไม่ถูกต้อง") }
        static var registeredRequiredTitle: String { String(localized: "ต้องเป็นสมาชิกก่อน") }
        static var registeredRequiredReview: String { String(localized: "ผู้เยี่ยมชมอ่านรีวิวได้ แต่การเขียนรีวิวต้องยืนยันเบอร์โทรก่อน เพื่อให้รีวิวน่าเชื่อถือ") }
        static var registeredRequiredSubmit: String { String(localized: "การแนะนำสถานที่ใหม่ต้องยืนยันเบอร์โทรก่อน") }
        static var registeredRequiredClaim: String { String(localized: "การขอยืนยันความเป็นเจ้าของต้องยืนยันเบอร์โทรก่อน") }
    }

    enum Submission {
        static var title: String { String(localized: "แนะนำสถานที่") }
        static var intro: String { String(localized: "สถานที่ใหม่จะแสดงบน Nanglen หลังทีมงานตรวจสอบและอนุมัติแล้วเท่านั้น") }
        static var searchMaps: String { String(localized: "ค้นหาใน Apple Maps") }
        static var searchMapsPlaceholder: String { String(localized: "ชื่อสถานที่ใน Apple Maps") }
        static var pinHint: String { String(localized: "เลื่อนแผนที่ให้หมุดอยู่ตรงทางเข้าสถานที่") }
        static var notOnNanglen: String { String(localized: "จาก Apple Maps · ยังไม่อยู่ใน Nanglen") }
        static var alreadyOnNanglen: String { String(localized: "มีอยู่ใน Nanglen แล้ว") }
        static var name: String { String(localized: "ชื่อสถานที่ *") }
        static var category: String { String(localized: "ประเภท *") }
        static var address: String { String(localized: "ที่อยู่ *") }
        static var description: String { String(localized: "ทำไมถึงแนะนำ (ไม่บังคับ)") }
        static var website: String { String(localized: "เว็บไซต์หรือโซเชียล (https://…)") }
        static var phone: String { String(localized: "เบอร์ติดต่อ (ไม่บังคับ)") }
        static var note: String { String(localized: "ข้อความถึงทีมงาน (ไม่บังคับ)") }
        static var photos: String { String(localized: "รูปภาพ (สูงสุด 5)") }
        static var submit: String { String(localized: "ส่งให้ทีมงานตรวจสอบ") }
        static var resubmit: String { String(localized: "ส่งตรวจสอบอีกครั้ง") }
        static var submitted: String { String(localized: "ส่งแล้ว · รอทีมงานตรวจสอบ") }
        static var submittedMessage: String { String(localized: "ติดตามสถานะได้ที่ โปรไฟล์ › สถานที่ที่ฉันแนะนำ") }
        static var alreadyListedTitle: String { String(localized: "สถานที่นี้มีอยู่แล้ว") }
        static var alreadyListedMessage: String { String(localized: "สถานที่นี้อยู่ใน Nanglen แล้ว คุณสามารถเปิดดูและเขียนรีวิวได้เลย") }
        static var openVenue: String { String(localized: "เปิดดูสถานที่") }
        static func possibleDuplicates(_ names: String) -> String { String(localized: "อาจซ้ำกับ: \(names) ทีมงานจะตรวจสอบให้") }
        static var nameRequired: String { String(localized: "กรอกชื่อสถานที่") }
        static var categoryRequired: String { String(localized: "เลือกประเภท") }
        static var locationRequired: String { String(localized: "ปักหมุดตำแหน่งบนแผนที่") }
        static var invalidWebsite: String { String(localized: "ลิงก์ต้องขึ้นต้นด้วย https://") }
        static var textTooLong: String { String(localized: "ข้อความยาวเกินไป") }
        static var useThisPlace: String { String(localized: "ใช้สถานที่นี้") }
        static var mine: String { String(localized: "สถานที่ที่ฉันแนะนำ") }
        static var mineEmpty: String { String(localized: "ยังไม่มีสถานที่ที่แนะนำ") }
        static var withdraw: String { String(localized: "ถอนคำขอ") }
        static var editAndResubmit: String { String(localized: "แก้ไขและส่งใหม่") }
        static var adminFeedback: String { String(localized: "ความเห็นจากทีมงาน") }
    }

    enum SubmissionStatusText {
        static var draft: String { String(localized: "ฉบับร่าง") }
        static var pending: String { String(localized: "รอทีมงานตรวจสอบ") }
        static var needsChanges: String { String(localized: "ต้องแก้ไข") }
        static var approved: String { String(localized: "อนุมัติแล้ว") }
        static var rejected: String { String(localized: "ไม่อนุมัติ") }
        static var duplicate: String { String(localized: "ซ้ำกับที่มีอยู่") }
        static var withdrawn: String { String(localized: "ถอนแล้ว") }
    }

    enum Claim {
        static var title: String { String(localized: "ยืนยันความเป็นเจ้าของ") }
        static var intro: String { String(localized: "ทีมงานจะตรวจสอบหลักฐานก่อนให้สิทธิ์ดูแลสถานที่ เจ้าของไม่สามารถแก้ไขหรือลบรีวิวของผู้ใช้ได้") }
        static var businessName: String { String(localized: "ชื่อธุรกิจ *") }
        static var role: String { String(localized: "บทบาท") }
        static var owner: String { String(localized: "เจ้าของ") }
        static var manager: String { String(localized: "ผู้จัดการ") }
        static var editor: String { String(localized: "ผู้ดูแลข้อมูล") }
        static var contact: String { String(localized: "ช่องทางติดต่อกลับ (ไม่บังคับ)") }
        static var evidence: String { String(localized: "หลักฐาน เช่น เลขทะเบียนพาณิชย์ หรือลิงก์เพจทางการ") }
        static var submit: String { String(localized: "ส่งคำขอ") }
        static var submitted: String { String(localized: "ส่งคำขอแล้ว · รอทีมงานตรวจสอบ") }
        static var myClaims: String { String(localized: "คำขอเป็นเจ้าของสถานที่") }
        static var pending: String { String(localized: "รอตรวจสอบ") }
        static var approved: String { String(localized: "อนุมัติแล้ว") }
        static var rejected: String { String(localized: "ไม่อนุมัติ") }
        static var withdrawn: String { String(localized: "ถอนแล้ว") }
    }

    enum Admin {
        static var title: String { String(localized: "คิวตรวจสอบ") }
        static var submissions: String { String(localized: "สถานที่ใหม่") }
        static var claims: String { String(localized: "คำขอเจ้าของ") }
        static var flagged: String { String(localized: "รีวิวที่ถูกรายงาน") }
        static var empty: String { String(localized: "ไม่มีรายการรอตรวจสอบ") }
        static var approve: String { String(localized: "อนุมัติ") }
        static var reject: String { String(localized: "ไม่อนุมัติ") }
        static var requestChanges: String { String(localized: "ขอให้แก้ไข") }
        static var markDuplicate: String { String(localized: "ซ้ำกับสถานที่นี้") }
        static var duplicates: String { String(localized: "สถานที่ใกล้เคียงที่อาจซ้ำ") }
        static var noDuplicates: String { String(localized: "ไม่พบสถานที่ใกล้เคียงที่อาจซ้ำ") }
        static var submitter: String { String(localized: "ผู้แนะนำ") }
        static func submitterStats(_ name: String, _ approved: Int, _ total: Int) -> String { String(localized: "\(name) · อนุมัติ \(approved) จาก \(total) รายการ") }
        static var reasonTitle: String { String(localized: "เหตุผล (ผู้ส่งจะเห็นข้อความนี้)") }
        static var notePlaceholder: String { String(localized: "หมายเหตุ (ไม่บังคับ)") }
        static var likelyDuplicate: String { String(localized: "พบสถานที่ที่น่าจะซ้ำในระยะ 50 ม. อนุมัติต่อหรือไม่?") }
        static var approveAnyway: String { String(localized: "อนุมัติต่อ") }
        static var hide: String { String(localized: "ซ่อนรีวิว") }
        static var removeReview: String { String(localized: "ลบรีวิว") }
        static var dismiss: String { String(localized: "ยกฟ้อง (คงไว้)") }
        static var done: String { String(localized: "บันทึกการตัดสินแล้ว") }
        static var history: String { String(localized: "ประวัติการตรวจสอบ") }
        static func photosCount(_ count: Int) -> String { String(localized: "รูปภาพ \(count) รูป") }
        static func dupCount(_ count: Int) -> String { String(localized: "อาจซ้ำ \(count)") }
        static func flags(_ count: Int, _ reasons: String) -> String { String(localized: "\(count) รายงาน · \(reasons)") }
    }

    enum Saved {
        static var title: String { String(localized: "บันทึกไว้") }
        static var emptyTitle: String { String(localized: "ยังไม่มีสถานที่ที่บันทึกไว้") }
        static var emptyMessage: String { String(localized: "แตะ ♡ ในหน้าสถานที่เพื่อเก็บไว้ดูภายหลัง") }
        static var guestNote: String { String(localized: "บันทึกในฐานะผู้เยี่ยมชม · ยืนยันเบอร์โทรเพื่อเก็บไว้ข้ามอุปกรณ์") }
        static var offline: String { String(localized: "ออฟไลน์ · แสดงรายการที่บันทึกไว้ในเครื่อง") }
    }

    enum Profile {
        static var title: String { String(localized: "โปรไฟล์") }
        static var registered: String { String(localized: "สมาชิก · ยืนยันเบอร์แล้ว") }
        static var notVerified: String { String(localized: "ยังไม่ได้ยืนยันเบอร์โทร") }
        static var admin: String { String(localized: "ผู้ดูแลระบบ") }
        static var businessOwner: String { String(localized: "เจ้าของธุรกิจ") }
        static var contributions: String { String(localized: "การมีส่วนร่วม") }
        static var savedCount: String { String(localized: "สถานที่ที่บันทึกไว้") }
        static var reviewsCount: String { String(localized: "รีวิวของฉัน") }
        static var addPlace: String { String(localized: "แนะนำสถานที่ใหม่") }
        static var mySubmissions: String { String(localized: "สถานที่ที่ฉันแนะนำ") }
        static var myBusinesses: String { String(localized: "ธุรกิจที่ฉันดูแล") }
        static var moderation: String { String(localized: "คิวตรวจสอบของทีมงาน") }
        static var editName: String { String(localized: "เปลี่ยนชื่อที่แสดง") }
        static var settings: String { String(localized: "การตั้งค่า") }
        static var location: String { String(localized: "สิทธิ์ตำแหน่ง") }
        static var locationOn: String { String(localized: "อนุญาตขณะใช้แอป") }
        static var locationOff: String { String(localized: "ไม่อนุญาต") }
        static var locationNotAsked: String { String(localized: "ยังไม่ได้ขอ") }
        static var clearCache: String { String(localized: "ล้างข้อมูลแคช") }
        static var clearCacheConfirm: String { String(localized: "ล้างข้อมูลสถานที่ที่บันทึกไว้ในเครื่องและฉบับร่าง ข้อมูลบนเซิร์ฟเวอร์ไม่ถูกลบ") }
        static var cacheCleared: String { String(localized: "ล้างแคชแล้ว") }
        static var backend: String { String(localized: "เซิร์ฟเวอร์") }
        static var demoBackend: String { String(localized: "โหมดสาธิต (ข้อมูลในเครื่อง)") }
        static var demoExplain: String { String(localized: "ยังไม่ได้ตั้งค่า Supabase แอปจึงใช้เซิร์ฟเวอร์จำลองในเครื่อง ข้อมูลไม่ถูกแชร์กับผู้ใช้อื่น") }
        static func demoAdminHint(_ phone: String) -> String { String(localized: "โหมดสาธิต: ยืนยันเบอร์ \(phone) เพื่อทดลองสิทธิ์ผู้ดูแล") }
        static var signOut: String { String(localized: "ออกจากระบบ") }
        static var signOutConfirm: String { String(localized: "ออกจากระบบแล้วจะกลับเป็นผู้เยี่ยมชมใหม่ ข้อมูลของบัญชีจะยังอยู่บนเซิร์ฟเวอร์และกลับมาได้เมื่อยืนยันเบอร์เดิม") }
        static var version: String { String(localized: "เวอร์ชัน") }
        static var privacy: String { String(localized: "เราใช้ตำแหน่งเฉพาะตอนค้นหาและตอนยืนยันการไปจริง ไม่เก็บประวัติการเดินทาง") }
    }

    enum Errors {
        static func message(for error: BackendError) -> String {
            switch error {
            case .notConfigured: String(localized: "ยังไม่ได้ตั้งค่าเซิร์ฟเวอร์")
            case .notAuthenticated: String(localized: "เซสชันหมดอายุ ลองเปิดแอปใหม่")
            case .registrationRequired: L10n.Account.registeredRequiredTitle
            case .adminRequired: String(localized: "ต้องเป็นผู้ดูแลระบบ")
            case .rateLimited: String(localized: "ทำรายการถี่เกินไป ลองใหม่ภายหลัง")
            case .notFound: String(localized: "ไม่พบข้อมูล อาจถูกลบหรือเปลี่ยนสถานะแล้ว")
            case .venueNotReviewable: String(localized: "สถานที่นี้ยังรับรีวิวไม่ได้")
            case .challengeExpired, .challengeConsumed, .verificationConsumed, .verificationExpired, .verificationInvalid:
                L10n.Review.reverify
            case .invalidInput(let code): inputMessage(code)
            case .invalidStatusTransition: String(localized: "สถานะเปลี่ยนไปแล้ว รีเฟรชแล้วลองใหม่")
            case .likelyDuplicate: L10n.Admin.likelyDuplicate
            case .providerRefExists: String(localized: "สถานที่นี้ผูกกับ Apple Maps ที่มีอยู่แล้ว ให้ทำเครื่องหมายว่าซ้ำ")
            case .reviewRemoved: String(localized: "รีวิวของคุณสำหรับที่นี่ถูกลบโดยทีมงาน")
            case .phoneAlreadyInUse: String(localized: "เบอร์นี้ผูกกับบัญชีอื่นแล้ว เราจะไม่รวมบัญชีโดยอัตโนมัติ กรุณาติดต่อทีมงาน")
            case .invalidOTP: String(localized: "รหัสไม่ถูกต้องหรือหมดอายุ")
            case .network: String(localized: "เชื่อมต่ออินเทอร์เน็ตไม่ได้")
            case .server: L10n.Common.somethingWentWrong
            }
        }

        static func inputMessage(_ code: String) -> String {
            switch code {
            case "invalid_rating": L10n.Review.ratingRequired
            case "too_many_tags": L10n.Review.tooManyTags
            case "body_too_long": String(localized: "ความคิดเห็นยาวเกิน 500 ตัวอักษร")
            case "name_required": L10n.Submission.nameRequired
            case "category_required": L10n.Submission.categoryRequired
            case "invalid_coordinate": L10n.Submission.locationRequired
            case "invalid_website_url": L10n.Submission.invalidWebsite
            case "reason_required": String(localized: "กรุณาระบุเหตุผล")
            case "invalid_phone": L10n.Account.invalidPhone
            case "claim_already_pending": String(localized: "คุณมีคำขอที่รอตรวจสอบสำหรับสถานที่นี้แล้ว")
            case "cannot_flag_own_review": String(localized: "รายงานรีวิวของตัวเองไม่ได้")
            case "file_too_large": String(localized: "ไฟล์ใหญ่เกิน 5 MB")
            case "too_many_photos": String(localized: "รูปภาพเกินจำนวนที่กำหนด")
            default: L10n.Common.somethingWentWrong
            }
        }

        static func message(for error: Error) -> String {
            if let backend = error as? BackendError { return message(for: backend) }
            if error is URLError { return message(for: BackendError.network) }
            return L10n.Common.somethingWentWrong
        }
    }
}
