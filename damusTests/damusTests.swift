//
//  damusTests.swift
//  damusTests
//
//  Created by William Casarin on 2022-04-01.
//

import XCTest
@testable import damus


class damusTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testTestRelay() throws {
        Task { try await TestRelay.run() }
        let url = URL(string: "http://localhost:63876")!
        let expectation = self.expectation(description: "GET http://localhost:63876 returns 'It works!'")
        // Add a delay before sending the request
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                XCTAssertNil(error)
                XCTAssertNotNil(data)
                guard let data else { return }
                let str = String(data: data, encoding: .utf8)
                XCTAssertEqual(str, "It works!")
                expectation.fulfill()
            }
            task.resume()
        }
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testEventVerify() throws {
        let test_valid_note_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3","created_at":1753898578,"content":"Test 1102","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[]}
        """
        let test_invalid_note_tampered_sig_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3","created_at":1753898578,"content":"Test 1102","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f153","tags":[]}
        """
        let test_invalid_note_tampered_id_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e600","created_at":1753898578,"content":"Test 1102","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[]}
        """
        let test_invalid_note_tampered_date_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3","created_at":1753898579,"content":"Test 1102","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[]}
        """
        let test_invalid_note_tampered_pubkey_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3","created_at":1753898578,"content":"Test 1102","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084b","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[]}
        """
        let test_invalid_note_tampered_content_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3","created_at":1753898578,"content":"Test 1103","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[]}
        """
        let test_invalid_note_tampered_kind_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3","created_at":1753898578,"content":"Test 1102","kind":2,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[]}
        """
        let test_invalid_note_tampered_tags_text = """
        {"id":"f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3","created_at":1753898578,"content":"Test 1102","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[["t", "foo"]]}
        """
        
        let test_valid_note = NdbNote.owned_from_json(json: test_valid_note_text)!
        let test_invalid_note_tampered_sig = NdbNote.owned_from_json(json: test_invalid_note_tampered_sig_text)!
        var test_invalid_note_tampered_id = NdbNote.owned_from_json(json: test_invalid_note_tampered_id_text)!
        let test_invalid_note_tampered_date = NdbNote.owned_from_json(json: test_invalid_note_tampered_date_text)!
        let test_invalid_note_tampered_pubkey = NdbNote.owned_from_json(json: test_invalid_note_tampered_pubkey_text)!
        let test_invalid_note_tampered_content = NdbNote.owned_from_json(json: test_invalid_note_tampered_content_text)!
        let test_invalid_note_tampered_kind = NdbNote.owned_from_json(json: test_invalid_note_tampered_kind_text)!
        let test_invalid_note_tampered_tags = NdbNote.owned_from_json(json: test_invalid_note_tampered_tags_text)!
        
        XCTAssertEqual(test_valid_note.verify(), true)
        XCTAssertEqual(test_invalid_note_tampered_sig.verify(), false)
        XCTAssertEqual(test_invalid_note_tampered_id.verify(), false)
        XCTAssertEqual(test_invalid_note_tampered_date.verify(), false)
        XCTAssertEqual(test_invalid_note_tampered_pubkey.verify(), false)
        XCTAssertEqual(test_invalid_note_tampered_content.verify(), false)
        XCTAssertEqual(test_invalid_note_tampered_kind.verify(), false)
        XCTAssertEqual(test_invalid_note_tampered_tags.verify(), false)
    }

    func testIdEquality() throws {
        let pubkey = test_pubkey
        let ev = test_note

        let pubkey_same = Pubkey(Data([0xf7, 0xda, 0xc4, 0x6a, 0xa2, 0x70, 0xf7, 0x28, 0x76, 0x06, 0xa2, 0x2b, 0xeb, 0x4d, 0x77, 0x25, 0x57, 0x3a, 0xfa, 0x0e, 0x02, 0x8c, 0xdf, 0xac, 0x39, 0xa4, 0xcb, 0x23, 0x31, 0x53, 0x7f, 0x66]))

        XCTAssertEqual(pubkey.hashValue, pubkey_same.hashValue)
        XCTAssertEqual(pubkey, pubkey_same)
    }

    func testRandomBytes() {
        let bytes = random_bytes(count: 32)
        
        print("testRandomBytes \(hex_encode(bytes))")
        XCTAssertEqual(bytes.count, 32)
    }
    
    func testTrimSuffix() {
        let txt = "   bobs   "
        
        XCTAssertEqual(trim_suffix(txt), "   bobs")
    }
    
    func testParseMentionWithMarkdown() {
        let md = """
        Testing markdown in damus
        
        **bold**

        _italics_

        `monospace`

        # h1

        ## h2

        ### h3

        * list1
        * list2

        > some awesome quote

        [my website](https://jb55.com)
        """
        
        let parsed = parse_note_content(content: .content(md, nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        
        XCTAssertTrue(parsed[0].isText)
        XCTAssertFalse(parsed[0].isURL)
        
        XCTAssertTrue(parsed[1].isURL)
        XCTAssertFalse(parsed[1].isText)
        
        XCTAssertTrue(parsed[2].isText)
        XCTAssertFalse(parsed[2].isURL)
    }

    func testStringArrayStorage() {
        let key = "test_key_string_values"
        let scoped_key = setting_property_key(key: key)

        let res = setting_set_property_value(scoped_key: scoped_key, old_value: [], new_value: ["a"])
        XCTAssertEqual(res, ["a"])

        let got = setting_get_property_value(key: key, scoped_key: scoped_key, default_value: [String]())
        XCTAssertEqual(got, ["a"])

        _ = setting_set_property_value(scoped_key: scoped_key, old_value: got, new_value: ["a", "b", "c"])
        let got2 = setting_get_property_value(key: key, scoped_key: scoped_key, default_value: [String]())
        XCTAssertEqual(got2, ["a", "b", "c"])
    }

    func testBech32Url()  {
        let parsed = decode_nostr_uri("nostr:npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s")
        
        let pk = Pubkey(hex:"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        XCTAssertEqual(parsed, .ref(.pubkey(pk)))
    }
    
    func testSaveRelayFilters() {
        var filters = Set<RelayFilter>()

        let filter1 = RelayFilter(timeline: .search, relay_id: RelayURL("wss://abc.com")!)
        let filter2 = RelayFilter(timeline: .home, relay_id: RelayURL("wss://abc.com")!)
        filters.insert(filter1)
        filters.insert(filter2)

        save_relay_filters(test_pubkey, filters: filters)
        let loaded_filters = load_relay_filters(test_pubkey)!

        XCTAssertEqual(loaded_filters.count, 2)
        XCTAssertTrue(loaded_filters.contains(filter1))
        XCTAssertTrue(loaded_filters.contains(filter2))
        XCTAssertEqual(filters, loaded_filters)
    }
    
    func testParseUrl() {
        let parsed = parse_note_content(content: .content("a https://jb55.com b", nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        
        let url = URL(string: "https://jb55.com")
        XCTAssertNotNil(url)
        
        XCTAssertEqual(parsed[1].asURL, url)
    }
    
    func testParseUrlEnd() {
        let parsed = parse_note_content(content: .content("a https://jb55.com", nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        
        XCTAssertEqual(parsed[0].asString, "a ")
        
        let url = URL(string: "https://jb55.com")
        XCTAssertNotNil(url)
        
        XCTAssertEqual(parsed[1].asURL, url)
    }
    
    func testParseUrlStart() {
        let parsed = parse_note_content(content: .content("https://jb55.com br",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        
        let testURL = URL(string: "https://jb55.com")
        XCTAssertNotNil(testURL)
        
        XCTAssertEqual(parsed[0].asURL, testURL)
        
        XCTAssertEqual(parsed[1].asText, " br")
    }
    
    func testNoParseUrlWithOnlyWhitespace() {
        let testString = "https://  "
        let parsed = parse_note_content(content: .content(testString,nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertFalse(parsed[0].isURL)
        XCTAssertEqual(parsed[0].asText, testString)
    }
    
    func testNoParseUrlTrailingCharacters() {
        let testString = "https://foo.bar, "
        let parsed = parse_note_content(content: .content(testString,nil))!.blocks

        let testURL = URL(string: "https://foo.bar")
        XCTAssertNotNil(testURL)
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[0].asURL, testURL)
    }


    /*
    func testParseMentionBlank() {
        let parsed = parse_note_content(content: "", tags: [["e", "event_id"]]).blocks
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 0)
    }
     */

    func testMakeHashtagPost() {
        let post = NostrPost(content: "#damus some content #bitcoin derp #かっこいい wow", tags: [])
        let ev = post.to_event(keypair: test_keypair_full)!

        XCTAssertEqual(ev.tags.count, 3)
        XCTAssertEqual(ev.content, "#damus some content #bitcoin derp #かっこいい wow")
        XCTAssertEqual(ev.tags[0][0].string(), "t")
        XCTAssertEqual(ev.tags[0][1].string(), "damus")
        XCTAssertEqual(ev.tags[1][0].string(), "t")
        XCTAssertEqual(ev.tags[1][1].string(), "bitcoin")
        XCTAssertEqual(ev.tags[2][0].string(), "t")
        XCTAssertEqual(ev.tags[2][1].string(), "かっこいい")
    }

    func testParseMentionOnlyText() {
        let tags = [["e", "event_id"]]
        let ev = NostrEvent(content: "there is no mention here", keypair: test_keypair, tags: tags)!
        let parsed = parse_note_content(content: .init(note: ev, keypair: test_keypair))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].asText, "there is no mention here")
        
        guard case .text(let txt) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        
        XCTAssertEqual(txt, "there is no mention here")
    }
    
    func testTagGeneration_Note_ContainsNoTags() {
        let ev = createEventFromContentString("note1h865g8j9egu30yequqp3e7ccudq8seeaes7nuw3m82vpwc9226tqtudlvp")
        
        XCTAssertEqual(ev.tags.count, 0)
    }
    
    func testTagGeneration_Nevent_ContainsNoTags() {
        let ev = createEventFromContentString("nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm")
        
        XCTAssertEqual(ev.tags.count, 0)
    }
    
    func testTagGeneration_Npub_ContainsPTag() {
        let ev = createEventFromContentString("npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6")
        
        XCTAssertEqual(ev.tags.count, 1)
        XCTAssertEqual(ev.tags[0][0].string(), "p")
        XCTAssertEqual(ev.tags[0][1].string(), "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
    }
    
    func testTagGeneration_Nprofile_ContainsPTag() {
        let ev = createEventFromContentString("nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p")
        
        XCTAssertEqual(ev.tags.count, 1)
        XCTAssertEqual(ev.tags[0][0].string(), "p")
        XCTAssertEqual(ev.tags[0][1].string(), "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
    }
    
    func testTagGeneration_Naddr_ContainsATag(){
        let ev = createEventFromContentString("naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld")
        
        XCTAssertEqual(ev.tags.count, 1)
        XCTAssertEqual(ev.tags[0][0].string(), "a")
        XCTAssertEqual(ev.tags[0][1].string(), "30023:599f67f7df7694c603a6d0636e15ebc610db77dcfd47d6e5d05386d821fb3ea9:1700730909108")
    }

}

private func createEventFromContentString(_ content: String) -> NostrEvent {
    let post = NostrPost(content: content, tags: [])
    guard let ev = post.to_event(keypair: test_keypair_full) else {
        XCTFail("Could not create event")
        return test_note
    }
    
    return ev
}
