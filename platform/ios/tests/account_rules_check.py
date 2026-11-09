#!/usr/bin/env python3
"""Checks the decisions of platform/ios/App/AccountModel.m against the reply shapes in the desktop
launcher (horizon/launcher/src/account/tests.rs). A Python copy of the logic: it checks the rules,
not the Objective-C text, which only CI compiles. Run: python3 platform/ios/tests/account_rules_check.py
Keep this and AccountModel.m in step."""
import json
def obj(b):
    try:
        v=json.loads(b) if b else None
    except Exception: return None
    return v if isinstance(v,dict) else None
def s(d,k):
    v=(d or {}).get(k); return v if isinstance(v,str) and v else None
def num(d,k):
    v=(d or {}).get(k)
    if isinstance(v,bool): return None
    if isinstance(v,(int,float)): return v
    if isinstance(v,str):
        try: return int(v)
        except: return None
def oauth(v):
    e=s(v,"error")
    m={"authorization_declined":"Sign-in was declined in the browser.","expired_token":"The sign-in code expired. Start again.","bad_verification_code":"The sign-in code was not recognised. Start again.","invalid_grant":"SIGN_IN_AGAIN","invalid_client":"refused","unauthorized_client":"refused"}
    if e in m: return m[e]
    return "Microsoft sign-in failed (%s)."%e if e else "Microsoft sign-in failed."
def device(b):
    v=obj(b); u,d=s(v,"user_code"),s(v,"device_code")
    if not u or not d: return None
    i=num(v,"interval"); e=num(v,"expires_in")
    return dict(user=u,dev=d,uri=s(v,"verification_uri") or "https://www.microsoft.com/link",interval=max(1,i) if i is not None else 5,expires=e if e is not None else 900)
def poll(b,status):
    v=obj(b); e=s(v,"error")
    if e=="authorization_pending": return "pending"
    if e=="slow_down": return "slow"
    if status==200 and s(v,"access_token") and s(v,"refresh_token"): return "in"
    return "stopped:"+(oauth(v) if v else "Microsoft sign-in failed.")
def xsts(b,status):
    v=obj(b) or {}
    t=s(v,"Token"); xui=(v.get("DisplayClaims") or {}).get("xui") if isinstance(v.get("DisplayClaims"),dict) else None
    first=xui[0] if isinstance(xui,list) and xui and isinstance(xui[0],dict) else None
    u=s(first,"uhs")
    if status==200 and t and u: return ("ok",t,u)
    x=num(v,"XErr")
    return ("msg",x)
def owns(b):
    items=(obj(b) or {}).get("items")
    if not isinstance(items,list): return False
    return any(isinstance(i,dict) and i.get("name") in("game_minecraft","product_minecraft") for i in items)
def may(signed,own,reach,fresh):
    if not signed: return False
    return fresh if reach else own
J = json.dumps
# the desktop tests' own replies
assert device(J({"user_code":"ABCD-EFGH","device_code":"dev-1","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":1}))["interval"]==1
assert device(J({"user_code":"A","device_code":"d","interval":0}))["interval"]==1       # never faster than 1 s
assert device(J({"user_code":"A","device_code":"d"}))["interval"]==5                      # absent = 5
assert device(J({"user_code":"A"})) is None and device(b"") is None and device(b"[]") is None
assert poll(J({"error":"authorization_pending"}),400)=="pending"
assert poll(J({"error":"slow_down"}),400)=="slow"
assert poll(J({"access_token":"a","refresh_token":"r"}),200)=="in"
assert poll(J({"access_token":"a"}),200).startswith("stopped")   # no refresh token is not a sign-in
assert poll(J({"access_token":"a","refresh_token":"r"}),500).startswith("stopped")
assert "declined" in poll(J({"error":"authorization_declined"}),400)
assert poll(b"<html>",502)=="stopped:Microsoft sign-in failed."
assert xsts(J({"Token":"xsts-token","DisplayClaims":{"xui":[{"uhs":"uhs-1","xid":"1"}]}}),200)==("ok","xsts-token","uhs-1")
assert xsts(J({"Identity":"0","XErr":2148916238,"Message":""}),401)==("msg",2148916238)
assert xsts(J({"Token":"t","DisplayClaims":{"xui":[]}}),200)[0]=="msg"                   # no uhs
assert xsts(J({"Token":"t","DisplayClaims":{"xui":[{"uhs":"u"}]}}),401)[0]=="msg"        # not 200
assert owns(J({"items":[{"name":"game_minecraft"}],"signature":"x"}))
assert owns(J({"items":[{"name":"x"},{"name":"product_minecraft"}]}))
assert not owns(J({"items":[]})) and not owns(J({"items":[{"name":"other"}]})) and not owns(b"junk") and not owns(J({"items":"game_minecraft"}))
# the gate
assert not may(False,True,True,True)        # no account
assert may(True,False,True,True)            # fresh yes wins over an old no
assert not may(True,True,True,False)        # a fresh no blocks at once, even after a past yes
assert may(True,True,False,False)           # offline: the past yes stands
assert not may(True,False,False,False)      # offline and never passed: blocked
print("all mirror checks pass")
