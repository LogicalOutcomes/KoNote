Assert = require 'assert'
Async = require 'async'

{
	SymmetricEncryptionKey
	PrivateKey
	PublicKey
	generateSalt
} = require '../../persist/crypto'

describe 'generateSalt', ->
	it 'should generate unique salts', ->
		s1 = generateSalt()
		s2 = generateSalt()
		Assert.equal typeof s1, 'string'
		Assert s1.length is 32
		Assert.notEqual s1, s2

describe 'SymmetricEncryptionKey', ->
	# Super low iteration count to make the tests run quickly.
	# Salts would normally come from generateSalt()
	kdfParams1 = {
		iterationCount: Math.pow(2, 8)
		salt: 'nacl1'
	}
	kdfParams2 = {
		iterationCount: Math.pow(2, 8)
		salt: 'nacl2'
	}
	kdfParams3 = {
		iterationCount: Math.pow(2, 8)
		salt: new Buffer('nacl2', 'utf8')
	}

	it 'prevents accidental instantiation', ->
		Assert.throws ->
			new SymmetricEncryptionKey(new Buffer(32))

	it 'generates unique keys', ->
		k1 = SymmetricEncryptionKey.generate()
		k2 = SymmetricEncryptionKey.generate()
		Assert.notStrictEqual k1._rawKeyMaterial, k2._rawKeyMaterial

	it 'derives different keys for different passwords', (cb) ->
		Async.parallel [
			(cb) ->
				SymmetricEncryptionKey.derive 'password', kdfParams1, cb
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', kdfParams1, cb
		], (err, keys) ->
			if err then throw err

			Assert not keys[0]._rawKeyMaterial.equals keys[1]._rawKeyMaterial
			cb()

	it 'derives different keys for different salts', (cb) ->
		Async.parallel [
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', kdfParams1, cb
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', kdfParams2, cb
		], (err, keys) ->
			if err then throw err

			Assert not keys[0]._rawKeyMaterial.equals keys[1]._rawKeyMaterial
			cb()

	it 'derives the same key for buffer vs string', (cb) ->
		Async.parallel [
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', kdfParams2, cb
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', kdfParams3, cb
		], (err, keys) ->
			if err then throw err

			Assert keys[0]._rawKeyMaterial.equals keys[1]._rawKeyMaterial
			cb()

	it 'refuses to derive a key without a salt', (cb) ->
		SymmetricEncryptionKey.derive 'pass', {iterationCount: 10}, (err, k) ->
			Assert err
			Assert not k
			cb()

	it 'refuses to derive a key without an iteration count', (cb) ->
		SymmetricEncryptionKey.derive 'pass', {salt: 'nacl'}, (err, k) ->
			Assert err
			Assert not k
			cb()

	it 'imports keys from hex', ->
		keyText = 'symmkey-v1:abcdabcd12341234abcdabcd12341234abcdabcd12341234abcdabcd12341234'
		k = SymmetricEncryptionKey.import keyText
		Assert k

	it 'does not import keys with the wrong length', ->
		keyText = 'symmkey-v1:abcd'
		Assert.throws ->
			SymmetricEncryptionKey.import keyText

	it 'does not import keys from a different protocol version', ->
		keyText = 'symmkey-v2:abcdabcd12341234abcdabcd12341234abcdabcd12341234abcdabcd12341234'
		Assert.throws ->
			SymmetricEncryptionKey.import keyText

	it 'can export and import a key', ->
		k = SymmetricEncryptionKey.generate()
		keyText = k.export()
		k2 = SymmetricEncryptionKey.import(keyText)
		Assert k._rawKeyMaterial.equals k2._rawKeyMaterial

	it 'encrypts data with 33 bytes of overhead', ->
		myData = 'hello, world!'
		k = SymmetricEncryptionKey.generate()
		ct = k.encrypt myData
		Assert.strictEqual ct.length, myData.length + 33

		k2 = SymmetricEncryptionKey.import k.export()
		pt = k2.decrypt ct
		Assert.strictEqual pt.toString('utf8'), myData

	it 'refuses to decrypt an invalid auth tag', ->
		myData = 'hey there, world'
		k = SymmetricEncryptionKey.generate()
		ct = k.encrypt myData

		# Flip the bits of the last byte
		ct[ct.length - 1] = ct[ct.length - 1] ^ 0xFF

		Assert.throws ->
			pt = k2.decrypt ct

	it 'refuses to decrypt tampered data', ->
		myData = 'hey there, world'
		k = SymmetricEncryptionKey.generate()
		ct = k.encrypt myData

		# Flip the bits of a ciphertext byte
		ct[18] = ct[18] ^ 0xFF

		Assert.throws ->
			pt = k2.decrypt ct

	it 'refuses to decrypt with the wrong key', ->
		k1 = SymmetricEncryptionKey.generate()
		k2 = SymmetricEncryptionKey.generate()
		ct = k1.encrypt 'test'

		Assert.throws ->
			pt = k2.decrypt ct

	it 'erases the key material when requested', ->
		k = SymmetricEncryptionKey.generate()
		k.erase()
		Assert.strictEqual k._rawKeyMaterial, null

describe 'asymmetric crypto', ->
	testKey1 = "privkey-v1:" +
	"MIIJQQIBADANBgkqhkiG9w0BAQEFAASCCSswggknAgEAAoICAQDBnevNnVmlFJwRm9KrRhmTfbxpZOEoTuA2pyhItBzEkqxZe7nE3MOUymVe2n8PKZLyztcvKWDzFeCrMF5V8NRhHyv6eZHQW5MRBmuSb6h4wxYQL9G6zqIINGbmFrLAhXGsiGc0WazDhb6wcJH6TpC2bH1HVAb4Cf1BqLdU6bhchW4VSS7JlL2WqNYa4ElgaqhMm6RmGKvUgr6LOiaK86Lll-GLlXqXigtHxW4aQ0_NVRzQGbOETP_I-9kShvWqNd7OZ_AsH6-A5tS2zBV0L83QAOdeTSZLThOSdb5PaKCuLkSChoLa0IyAWtxfS0mzpODA1iJTxga2Z6iy8u_zptHTZ74Cv9zW8XsppVaKVFpUgjFcOmu6pM5-qMYYdpCi64lsv-mokCHBwlIQiecXeyP4FGh-RFyYflWD6eAuKACzqqhCOOlGVW6a4Bz8HqQZ87nzW4BGZVidlJ1GEEPllslDcgaPEJclUu6jDIgNSofxBo13rQ2tR51zil61PjsbjbHjzT9Osegu-OCnlw9KGHzvAkNJr5hLrM18dC36UAxBmNkodrilirmowVmOfLEsVAJVFtfg1tFgDXtkO5jHOnKnnlat2YOoK4x9xpOmkvUoVO_RxyUhEtbWdeUcFr_tC6yDlYvlzvxl9I6eNkUTbAIROKBR0ZDbgkLVLicWWA4pTQIDAQABAoICADay-dJOGOxlZS4oWp0eoc0kYZ1Y7a9okTl_ggcAM3xpf52MMdBnGi4n-_mPOwQ6l5RXUT22r_gc_yr98DjRX_7MQq1xuPsnU-YkbTGir_LmEo6iI9tl0ysEOunYEcoIKTQ4GQgWKZPXbicEtokDtyiCf-Yt3AYpNE5fbuPjX71ryMzkrv4uMl2k91ACe1hs6X0zH3_kim7wPQqyc_8fk67PeN3pbgfv7P3qzg9HYv08hXZZPHktE7phRFNSo4bhzz9658Rfc0K0c_XstEbt1nRkPPlMTHxL44WmFAz1Hyf2VE6X19IfxwHgKZAWggzpkMGJ_YqzUGQp5uQfdCDeyTo1rrD8rXu7QSZHJ_Xbyo6OsE6EJduoCNwhQMrZMjGUijXZQXr7XZgMspqwycb9D5GO8FJzE2aCR4k4qu-Ykjoy6mEAshjNw3PHokcRkU3aYch-q49DNK5JKwucdbwA5WTLMEaIePuIs_cZJQAZDHBqvijoAtR3NMB0jvlmyrExI66VbpcLgpTNZf2kuNZdy1P3nMCucnLC5VSrwzflXVzRC_GYvoVnUc23ONhadBYrS22s-ql8D7KI4HCN56o3TYCh7Vfx1VojYK6Ri94ZAUqEzoBevFp09UHleVQY4uVbjaiXm2rcl8MIH5cHoW8OFGxHSW8cdrRJc3HxekziNrb1AoIBAQDh8akslGpq2XDoVFORZsdntj8HhlvMnHvH6Z2VJBDGLdTpT2xDZNCMYI7s6qN2g7kKYTw1KJyReFVwWefeN3XJDarOwqKMdzvEOqD8G_oBFlIie2bBzB2toOQQYdvMpgsCHjpaG_t3CvYByfPH1u-Zhgv1YEhdX0Aei-i0fzAID4MnZKhocI60rsFU5vY6l6V9PkqEml-oyBr-vXcPEDh8hW_zjoNbAM-mCgi6LC1dXK8-vN589t9qYcZ13Z31wgwH2PO_k3v5A_TQ6owuFQEDqEj7wNLKKmpC7CG8_caQMc_j4145wCqRBhBammnWd2AvOBo-joHh9WHNRCLtpfWrAoIBAQDbX2MHEwwobrxJm7sSa8vqFu_zqWEkJtZJMrOR5IwwueYv9ZzIui9bfMpV-t3ApYT7Jw3NlX7FY2rWxORHMGtQRy0yjX05eFMwbgXauZOqzRHjv92mrKdPbXlN41TfkDhVEbCw5t9yyUieHoXwMN4m0r8FQx28K23SEL4pXHYRMCxlPWgUYNJVN-ZNyvuaSaTmjnF0wVEjjuuOzI-wk12SZVrJNWn9g8Rk39Y9kgaePsOpnZ93fsvKbGBkJ0-4elpcmW_yWTM5nXSW_1g-B_6jYbSpwWXXE_HSxxHaWJu51lCthiZv2nECko__hslkYam5-iNHNtNaiX6JoVan9HTnAoIBACK6Ow9gDG851pHPDD0n9_Qn3c4xR4DOeHQEozTeIznip3voujItl6RL3wvpEJDRtCo1QcTF5jKxtSgcmXfdPFxXnm5DGirO1L_XZxD419c88AjewK9-yPz74rHl6Juu1bhQnxVkgaUNaTxjJvYLQi5tnP7s-pJnZnqLdIvxlJdYkwcGAKB01GpPBeYfza65yjTS0y9IbvWJNCT9SARnsNbqx4c-20-scz4JAshiq-JSsZjJ_MRmSXaXaqKJGpNAbQrzvJswdviSNBm8Qyl-DvbZ8cXIIF30YPrCQnlC5DcbgOF8--mScLhznyXd3_CXzo_TZq1AyBPL3GlpVJkEThsCggEAIMUpB9-Ci2-vVNecpG3R8lAm3CFLT5k1nY2jYYHgp0694iAwoZOei24i06E8CxEuwk3dM_7HBzmItjiHWVMUVNOtHsYgFLuywaNN4JSkSHmF2J3KwKE-BRF3c3koLpVetOaFnIeAjacf3-7zVyQVq3sD6gdSo89hAmZZ4dfcE0k8-Iqpx5GHGg_VqX1PBIdHyOEydZyDQGqTKavJMzlwWvQlEbWW9bX_WopNeLkdn_oERIw1TCZ2zvBNneh5cjdk1DxfirZkfpDU39GZHvsWwNVRpaIsUmq6TyBJvHJMIQCw4JsPltns09ONC0DZSNOGBTAmoPbBr96mNm0RgtlztQKCAQBstr6G9Og03ZWx-9LsdEYvzZXuXQdGyBn-Z9uHpPoA4hkaWBJhxFjO5AwBnUaLTrT2LmZcPVt8pa1fKN9T75BVJfryaj1EDlTVUbyjseFWNWDBKgD-BmYPL8pMG5uYE6i5ssnu8Xu4Psm0avXHQ0Z-5iqHZgYP5-ezgNgsJ8pKwRcMvs9yKKrY7Sg0RTpcHo-Le-zj7EDZVvRygIxOtdrgZ0sfgRG9voOLSGjpFfJz4QbEx3y5G7g4dQEBCPB5eWOcNLrI_6SEwFc6lwJifVAoMlqioalu4wGKRPTQVh93w4idyEQy_tynTQxbrV7dMKwZM3Flj_5o8Ot4hucGcmCL:" +
	"MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwZ3rzZ1ZpRScEZvSq0YZk328aWThKE7gNqcoSLQcxJKsWXu5xNzDlMplXtp_DymS8s7XLylg8xXgqzBeVfDUYR8r-nmR0FuTEQZrkm-oeMMWEC_Rus6iCDRm5haywIVxrIhnNFmsw4W-sHCR-k6Qtmx9R1QG-An9Qai3VOm4XIVuFUkuyZS9lqjWGuBJYGqoTJukZhir1IK-izomivOi5Zfhi5V6l4oLR8VuGkNPzVUc0BmzhEz_yPvZEob1qjXezmfwLB-vgObUtswVdC_N0ADnXk0mS04TknW-T2igri5EgoaC2tCMgFrcX0tJs6TgwNYiU8YGtmeosvLv86bR02e-Ar_c1vF7KaVWilRaVIIxXDpruqTOfqjGGHaQouuJbL_pqJAhwcJSEInnF3sj-BRofkRcmH5Vg-ngLigAs6qoQjjpRlVumuAc_B6kGfO581uARmVYnZSdRhBD5ZbJQ3IGjxCXJVLuowyIDUqH8QaNd60NrUedc4petT47G42x480_TrHoLvjgp5cPShh87wJDSa-YS6zNfHQt-lAMQZjZKHa4pYq5qMFZjnyxLFQCVRbX4NbRYA17ZDuYxzpyp55WrdmDqCuMfcaTppL1KFTv0cclIRLW1nXlHBa_7Qusg5WL5c78ZfSOnjZFE2wCETigUdGQ24JC1S4nFlgOKU0CAwEAAQ:" +
	"MIIJQgIBADANBgkqhkiG9w0BAQEFAASCCSwwggkoAgEAAoICAQDA3bx9bjp41XDB1tyKXXogyGaXGb2BmlU6-vc8PgGH39Tts79OwVd8BTWV4G7BSf2CDlA7PQiY77dOvBM09Dl1jPsgVe4LwjGgRPcw2FPSJEgljVaml5VBCXvR7d_eE9pL_PY1q0t4KNiSQ-29ko410NWNwdLZYsHqCaa96IIVPQ354fPZA9RJQ-Ec8TjMdu_vknvjZkrFnHEIXm3MgIBwqEfLIjmjA9ewoqXZYQJwMZ0siubTAHsHHKzy8nKiY9H2-JyWEdU9h16lJ-UdERioi8OvKtUtwV5F8Ze61p38LEBQDr50EXl04Ly-5B8lrQuJcHRjY9XbmOhTw4Jya2IfOzoyokogh-I1RA7bSs_gAsiEcmorpWwAGisOnXjCiqBwO9GdzifoBN9NSvOhCgH7uuCnkNaBbf8GnKfVAirphB9xvTeTJ5CfMFs9AXX3Imj7jbqp_0p41J59yll-1xRyccf8l3xPBETY-pop9ECBu9nAkwiW-_fdT7utWlmykOo4Pi6kzxXW_vZL2lRUxYTl_GeYnLcrchct2vXdSSgrl5dN3hMJ2U6QPELEvuDbeM3Ndr8KCkbe5Kj_LAU8TgDEFkzjyr6X02QTy3JYEE3lKxTJtPU6Shu3xY_DjFOxvUI9G1hgu0Kbj4aQMP9mpC4LZzg-sblClO0wXdubR63F_QIDAQABAoICACjPAjIcH70vlHM_blzMmKnVHXf9V07UBBK9xZB2okZIwzoknWchm8w_Ie57lZPKfxyEwM84A9iwaD39p6a9wmawFPbrl7nfNjbuQMuSCnJdgPKJLHuFeWxQgGWUCpln4_nOJZ6Hhyl-owyX2PcSyopyjK05BM9AiT1nG2P1jYjG6W0lNT6HA-UYusov9E-3Ht-3RAWCwHF9v6EAsgTib8rmoIJH1KA8kOfsEmGjmCt7JAGnxl2BLYb8t0-Uo1LfAi9avW83iMJDIXCat2zmECyhnh8zVfYfgz4Td4JuJPGVv2nxJLVUeTmUz_soM7r6GYXUSJw7JKYZfZczuCdTt2f8S_PFpbGJjGW7XgqXIOUJPkBc9iI3EZkXQEM8yvDSoHd-_u8_5grLaB1lm0bH6alZroObiWJHrTAc7b3y3-199Tts_XPu9xygKcSL5hPgXByeceo_8pZoBwOhEBuY6_dwq24FSXczojU-lZtuJ6axAJSqWRerABlzFf5-f6Dj5xAHt03jC6kjtkmES5v3HORDShxZWd40gvZ_HX8OEA7UEz3K6Jb6HjPbWxBiJLvICwoBR9M5ulhYD_ZzVbB-VYP4xzGZL65Ksq3KJk2hWFdUveNljDfwbIgwsa9-4mLMJWxl9TRdrkjGOSPva1wSC7NriK68dC8CU0H67w0_pko1AoIBAQDgC_97tOVb4r0ssgcuqWX3rRqflpELAHLawWkfIwUvmsN6gIoRnIpriNqa_5l584DeVi_WNWFEG4arnECWUPXXtLz6AHw2d5g3gz9RlCrb26nDMaqS9xMWMpcYCc69sIujKBKiBj-Z4bBL-97x7XcjUVOmF4oh-rcxyAv2GhcEfF2MTStP9DoRDwqLGil_m7QW9WShqTpMNZE-DAQczQn5jvghVPBrolte1POC3Wi1tScjlZIdJKeU7NEsYcsrnfI8JC2ggkAoM5WR8qMqFXylvIXctRUm4ts4ODNvI5wu_bNMpG-nfJ9g0QKXUrN-LP2XCODZ7YWl4IGF-ogNUt6nAoIBAQDcX1LRooUMd7N3a3zJLVwUF6LYjw37NxBcdsNmQiQeNLrZ0zkpBDL7g_VOATQf0spUhaTdjtWGOPEM8U_YbGDkNhp167ubZojSgt9Jq31T78EjYOfn_-jqwdzDVlcUSNlysNkzjilQjX4RiR4r5bL8Ykp_Npx-3oN9YyliqJazsl1ZHRfB0jVbDlCHdReP0DXJyNRFFFZ0mKdDeDeXaOfB_lTZLx7JmwnENmue6EscnhEwssEYiyqCqeARnfGWECUy19OaeVj48raW6Qf_yhv2EG4rABN6F2FWrlhVIIu73NBXGc3WTeyXiGmu4YbCsAm_WLufb4QszAbOjkYTSA67AoIBAQDGpXypN1Ogq6GlTleV5LY26nFPjBUf1w7-rDvDUq6XbbXiGLPSN6R3AckpYnS2rtLUzz_swjlyRKGb6JdPb4r57RMc6m83b8QzfBgZAbEabGHRYmjlk1GF_eb_djqq7yxvxej3ZWjgzD0esbwTbsOSOdpbykU8KWpiJgeM9cbwwD_FVOqRIm6Vj2t-t_yRWwFK1dqah0vcJCaaB9dhnd45Oa0BCKl-FV7D7zXVEvBzI6IHJ-d8FXLMVUiE_FRCYPFUp5MY3EN8IXh9Bc_rUU_KNyPM83VEnCFYcGQSJ1WkSGbADo-8xX8ePVL5zma8-bECR-ns727vCuZsXxxgC9jDAoIBAGHanh7iSKwhlvpnK1D1qFZvrGr3EuFDMSutvNRyeDFFftbsmQwihjTzAoExvaCH7Dod4fhTzXK9ZCQ4Hxld_qQ3dgZ4t6SoogbAAEBpOsyDwMJh7HgzRYzAqrO-agpi0tO_vaLL9IKFYb6NoW0ioRi62JOmf1VCnyaVWrIpZEnE4PiKF5uEKRcWwyFzGBRPAyNn3wIRptY9VsB56E1-UrLsqWaLKuOgyXRsKdu1EG1TrxRtu5qXaTf-ELYh6T2WS75I4fhM-_oHZJacQWYOq93Wq-TCMuPa7-kan7SlMAcqZQTYO3N2xKEA_NSf5kQbASkLULzaOtndewRLXsh_DbMCggEAOZnasa122NhC89P0ppyfDrZxm0TgpcAiY_aWVt0ZUO1D9wJ8Sc5wKuYHtbeOjUgP_AX0Bs6LJE6VYBjnvGAKQIxHuGuHfnHF9yp9xsH3FYydGYN47lZ4gXOpufGGd386Ov2EoB9F28GaMQy4Rkj9B8bw4jaDuKgv8bVYD_3V5fdU_ptw55mWLYaghPO3cXIkrkxCGrgHMHbeUGF2irn3dICtKgL8oSl-THAAvN0dmnvxiJ7o6-RiWS7z87_FbFpwSmQnGkbcnUB8hxGgxYJN8OVpZ_2T55b4IAd1CTZUx_EzWWIiq4LUNVhEBA_4h66ye0cp3gHWa7q_qW24CuxJtg:" +
	"MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwN28fW46eNVwwdbcil16IMhmlxm9gZpVOvr3PD4Bh9_U7bO_TsFXfAU1leBuwUn9gg5QOz0ImO-3TrwTNPQ5dYz7IFXuC8IxoET3MNhT0iRIJY1WppeVQQl70e3f3hPaS_z2NatLeCjYkkPtvZKONdDVjcHS2WLB6gmmveiCFT0N-eHz2QPUSUPhHPE4zHbv75J742ZKxZxxCF5tzICAcKhHyyI5owPXsKKl2WECcDGdLIrm0wB7Bxys8vJyomPR9viclhHVPYdepSflHREYqIvDryrVLcFeRfGXutad_CxAUA6-dBF5dOC8vuQfJa0LiXB0Y2PV25joU8OCcmtiHzs6MqJKIIfiNUQO20rP4ALIhHJqK6VsABorDp14woqgcDvRnc4n6ATfTUrzoQoB-7rgp5DWgW3_Bpyn1QIq6YQfcb03kyeQnzBbPQF19yJo-426qf9KeNSefcpZftcUcnHH_Jd8TwRE2PqaKfRAgbvZwJMIlvv33U-7rVpZspDqOD4upM8V1v72S9pUVMWE5fxnmJy3K3IXLdr13UkoK5eXTd4TCdlOkDxCxL7g23jNzXa_CgpG3uSo_ywFPE4AxBZM48q-l9NkE8tyWBBN5SsUybT1Okobt8WPw4xTsb1CPRtYYLtCm4-GkDD_ZqQuC2c4PrG5QpTtMF3bm0etxf0CAwEAAQ"
	testKey1NextVersion = 'privkey-v2' + testKey1['privkey-v1'.length...]

	describe 'PrivateKey', ->
		it 'prevents accidental instanciation', ->
			Assert.throws ->
				new PrivateKey('a', 'b', 'c', 'd')

		# Note: we cannot test @generate because it is implemented using the Web
		# Crypto API.

		it 'can import a key', ->
			Assert PrivateKey.import(testKey1) instanceof PrivateKey

		it 'fails to import keys for a different version', ->
			Assert.throws ->
				PrivateKey.import testKey1NextVersion

		it 'can export a key', ->
			Assert.strictEqual PrivateKey.import(testKey1).export(), testKey1

		it 'can provide the public key', ->
			Assert PrivateKey.import(testKey1).getPublicKey() instanceof PublicKey

	describe 'PublicKey', ->
		testPublicKey1 = PrivateKey.import(testKey1).getPublicKey()

		it 'prevents accidental instanciation', ->
			Assert.throws ->
				new PublicKey('a', 'b')

		it 'can export a key', ->
			Assert.strictEqual(typeof testPublicKey1.export(), 'string')

		it 'can import a key', ->
			Assert.strictEqual testPublicKey1.export(), PublicKey.import(testPublicKey1.export()).export()

	describe 'encryption', ->
		it 'can encrypt and decrypt', ->
			msg = new Buffer('abcnehunthunjtqhntuhoentuhoenthunoetkbjqnkntoehunteohuntoehuntjhn')

			privKey = PrivateKey.import(testKey1)
			pubKey = privKey.getPublicKey()

			ciphertext = pubKey.encrypt(msg)

			# 1-byte overhead from version number
			# 512-byte overhead from 4096-bit RSA
			# 33-byte overhead from symmetric encryption
			Assert.strictEqual ciphertext.length, msg.length + 1 + 512 + 33

			# should match original message
			Assert privKey.decrypt(ciphertext).equals(msg)

	# TODO sign and verify
	# TODO erase?
