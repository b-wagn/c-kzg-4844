{.used.}

import
  std/[streams, strutils],
  unittest2,
  stew/byteutils,
  ../kzg_abi,
  ./types

proc readSetup(): KzgSettings =
  var
    s = newFileStream(trustedSetupFile)
    g1MonomialBytes: array[FIELD_ELEMENTS_PER_BLOB * 48, byte]
    g1LagrangeBytes: array[FIELD_ELEMENTS_PER_BLOB * 48, byte]
    g2MonomialBytes: array[65 * 96, byte]

  doAssert(s.isNil.not,
    "FAILED TO OPEN: " & trustedSetupFile)

  let fieldElems = s.readLine().parseInt()
  doAssert fieldElems == FIELD_ELEMENTS_PER_BLOB
  let numG2 = s.readLine().parseInt()
  doAssert numG2 == 65

  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let z = hexToByteArray[48](s.readLine())
    g1LagrangeBytes[i*48 ..< i*48+48] = z[0..<48]

  for i in 0 ..< 65:
    let z = hexToByteArray[96](s.readLine())
    g2MonomialBytes[i*96 ..< i*96+96] = z[0..<96]

  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let z = hexToByteArray[48](s.readLine())
    g1MonomialBytes[i*48 ..< i*48+48] = z[0..<48]

  let res = load_trusted_setup(result,
    g1MonomialBytes[0].addr,
    g1LagrangeBytes[0].addr,
    FIELD_ELEMENTS_PER_BLOB,
    g2MonomialBytes[0].addr,
    65,
    0)

  doAssert(res == KZG_OK,
    "ERROR: " & $res)

proc readSetup(filename: string): KzgSettings =
  var file = open(filename)
  let ret =  load_trusted_setup_file(result, file, 0)
  doAssert ret == KZG_OK
  file.close()

proc createKateBlobs(s: KzgSettings, n: int): KateBlobs =
  for i in 0..<n:
    var blob: KzgBlob
    discard urandom(blob)
    for i in 0..<len(blob):
      # don't overflow modulus
      if blob[i] > MAX_TOP_BYTE and i %% BYTES_PER_FIELD_ELEMENT == 0:
        blob[i] = MAX_TOP_BYTE
    result.blobs.add(blob)

  for i in 0..<n:
    var kate: KzgCommitment
    doAssert blob_to_kzg_commitment(kate, result.blobs[i], s) == KZG_OK
    result.kates.add(kate)

let
  kzgs = readSetup()

suite "verify proof (abi)":
  let
    settings = readSetup(trustedSetupFile)

  test "verify batch proof success":
    var kb = kzgs.createKateBlobs(nblobs)
    var kp: array[nblobs, KzgProof]

    for i in 0..<nblobs:
      let res = compute_blob_kzg_proof(kp[i], kb.blobs[i], kb.kates[i], kzgs)
      check res == KZG_OK

    var ok: bool
    let res = verify_blob_kzg_proof_batch(ok,
                         kb.blobs[0].addr,
                         kb.kates[0].addr,
                         kp[0].addr,
                         csize_t(nblobs),
                         kzgs)
    check res == KZG_OK
    check ok

  test "verify batch proof failure":
    var kb = kzgs.createKateBlobs(nblobs)
    var kp: array[nblobs, KzgProof]

    for i in 0..<nblobs:
      let res = compute_blob_kzg_proof(kp[i], kb.blobs[i], kb.kates[i], kzgs)
      check res == KZG_OK

    var other = kzgs.createKateBlobs(nblobs)
    for i in 0..<nblobs:
      let res = compute_blob_kzg_proof(kp[i], other.blobs[i], other.kates[i], kzgs)
      check res == KZG_OK

    var ok: bool
    let res = verify_blob_kzg_proof_batch(ok,
                         kb.blobs[0].addr,
                         kb.kates[0].addr,
                         kp[0].addr,
                         csize_t(nblobs),
                         kzgs)
    check res == KZG_OK
    check ok == false

  test "verify blob proof":
    var kp: KzgProof
    var res = compute_blob_kzg_proof(kp, blob, commitment, kzgs)
    check res == KZG_OK

    var ok: bool
    res = verify_blob_kzg_proof(ok, blob, commitment, kp, kzgs)
    check res == KZG_OK
    check ok

  test "verify proof":
    var kp: KzgProof
    var ky: KzgBytes32
    var res = compute_kzg_proof(kp, ky, blob, inputPoint, kzgs)
    check res == KZG_OK
    check kp == proof
    check ky == claimedValue

    var ok: bool
    res = verify_kzg_proof(ok, commitment, inputPoint, claimedValue, kp, kzgs)
    check res == KZG_OK
    check ok

  free_trusted_setup(settings)
