from typing import Union

# retrieve the users local json settings. 
def get_user_settings() -> dict: pass


# set, or update a key value pair in the user settings. 
def set_user_settings_key(key: str, value: str) -> None: pass


# gets the current version of millennium
def version() -> str: pass


# gets the current version of millennium
def steam_path() -> str: pass

    
# Call a frontend method with list of params. The order of the params matter since js doesnt have kwargs
# Example usage:
#     Backend (Python):
#     -> 
#         value = Millennium.call_frontend_method("classname.method", params=[18, "USA"])
#         print(value) -> "method called"
#     Frontend (TSX || TS):
#     -> 
#         class classname {
#             static method(country: string, age: number) {
#                 console.log(`age: ${age}, country: ${country}`);
#                 return "method called"
#             }
#         }
#         export { classname }
# NOTES: 
#       Python does NOT abide by your types set in a function in typescript
#       if in python you call this method with [bool, string] instead of [string, number] you will have to manage that yourself
def call_frontend_method(method_name: str, params: Union[str, int, bool]): pass

